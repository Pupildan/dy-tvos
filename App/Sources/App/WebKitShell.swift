import Foundation
import UIKit
import SwiftUI
import ObjectiveC.runtime

/// 运行时动态构建极简 ObjC 类充当 WKNavigationDelegate（空实现，仅让 respondsToSelector 通过）。
/// 加载完成信号由 isLoading 轮询提供。
enum WebKitDelegateFactory {
    private static let commitIMP: @convention(c) (NSObject, Selector, NSObject, NSObject) -> Void = { _,_,_,_ in }
    private static let finishIMP: @convention(c) (NSObject, Selector, NSObject, NSObject) -> Void = { _,_,_,_ in }
    private static let failIMP:   @convention(c) (NSObject, Selector, NSObject, NSObject, NSObject) -> Void = { _,_,_,_,_ in }

    static func makeDelegate() -> NSObject {
        let className = "DYWKNavDelegate_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let pair = objc_allocateClassPair(NSObject.self, className, 0)!
        let cls: AnyClass = pair
        class_addMethod(cls, NSSelectorFromString("webView:didCommitNavigation:"), unsafeBitCast(commitIMP, to: IMP.self), "v@:@@")
        class_addMethod(cls, NSSelectorFromString("webView:didFinishNavigation:"), unsafeBitCast(finishIMP, to: IMP.self), "v@:@@")
        class_addMethod(cls, NSSelectorFromString("webView:didFailNavigation:withError:"), unsafeBitCast(failIMP, to: IMP.self), "v@:@@@")
        class_addMethod(cls, NSSelectorFromString("webView:didFailProvisionalNavigation:withError:"), unsafeBitCast(failIMP, to: IMP.self), "v@:@@@")
        objc_registerClassPair(pair)
        // 分配未初始化实例，随后用 initWithFrame: 单次初始化（不走 Swift init()，避免二次 init 陷阱）
        let obj = NSAllocateObject(cls, 0, nil) as! NSObject
        return obj
    }
}

/// A 路线外壳：运行时实例化私有 WKWebView，加载抖音桌面版。
/// 关键：CGRect 结构体参数不能走 perform（会按对象传递导致闪退），必须走 objc_msgSend 按 C 约定传 struct。
/// 焦点意图：本 VC 内无 Button；登录走手机扫码，不依赖遥控器操作网页。
final class WebKitShellViewController: UIViewController {
    private var status: ((String) -> Void)?
    private var pollTimer: Timer?
    private var lastLoading = false
    private weak var webView: UIView?
    private static var delegateKey: UInt8 = 0

    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    func setStatusHandler(_ handler: @escaping (String) -> Void) {
        status = handler
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        guard dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_LAZY) != nil,
              let WKWebViewCls: AnyClass = NSClassFromString("WKWebView"),
              let ConfigCls: AnyClass = NSClassFromString("WKWebViewConfiguration")
        else {
            status?("FAIL: 无法加载私有 WebKit / WKWebView")
            return
        }

        // config = [[WKWebViewConfiguration alloc] initWith... ] -> 分配 + init (无 struct 参数, msgSend 安全)
        let configRaw = NSAllocateObject(ConfigCls, 0, nil) as! NSObject
        let initSel = NSSelectorFromString("init")
        typealias InitFn = @convention(c) (NSObject, Selector) -> NSObject
        let callInit = unsafeBitCast(objc_msgSend, to: InitFn.self)
        let config = callInit(configRaw, initSel)

        // customUserAgent：先探测 setter 是否存在再 KVC，避免 unknown key 抛异常
        if config.responds(to: NSSelectorFromString("setCustomUserAgent:")) {
            config.setValue(WebKitShellViewController.desktopUA, forKey: "customUserAgent")
        }

        let navBar = UILabel()
        navBar.text = "douyin.com (desktop UA)"
        navBar.textColor = .black
        navBar.font = .systemFont(ofSize: 20, weight: .semibold)
        navBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navBar)

        // webView = [[WKWebView alloc] initWithFrame:view.bounds]; configuration 经 setter 注入
        // initWithFrame: 的 CGRect 必须经 msgSend 按 C 约定传 struct（perform 会当对象传 -> 闪退）
        let wvRaw = NSAllocateObject(WKWebViewCls, 0, nil) as! NSObject
        let frameSel = NSSelectorFromString("initWithFrame:")
        typealias FrameFn = @convention(c) (NSObject, Selector, CGRect) -> NSObject
        let callFrame = unsafeBitCast(objc_msgSend, to: FrameFn.self)
        let wvObj = callFrame(wvRaw, frameSel, view.bounds)

        if wvObj.responds(to: NSSelectorFromString("setConfiguration:")) {
            wvObj.setValue(config, forKey: "configuration")
        }

        guard let wvView = wvObj as? UIView else {
            status?("FAIL: WKWebView 实例无法转为 UIView")
            return
        }
        webView = wvView
        wvView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(wvView)
        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            navBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            wvView.topAnchor.constraint(equalTo: navBar.bottomAnchor, constant: 8),
            wvView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            wvView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            wvView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        let delegate = WebKitDelegateFactory.makeDelegate()
        wvView.setValue(delegate, forKey: "navigationDelegate")
        objc_setAssociatedObject(wvView, &WebKitShellViewController.delegateKey, delegate,
                                 .OBJC_ASSOCIATION_RETAIN)

        // loadRequest: 参数是对象，可安全走 perform
        let url = URL(string: "https://www.douyin.com/")!
        wvView.perform(NSSelectorFromString("loadRequest:"), with: NSURLRequest(url: url))
        status?("loading douyin.com ...")

        startPolling()
    }

    private func startPolling() {
        lastLoading = false
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let wv = self.webView else { return }
            let loading = (wv.value(forKey: "isLoading") as? Bool) ?? false
            if loading != self.lastLoading {
                self.lastLoading = loading
                if !loading { self.status?("poll: 加载完成 (二维码应已显示, 手机扫码登录)") }
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pollTimer?.invalidate(); pollTimer = nil
    }
}

/// SwiftUI 包装。
struct WebKitShellView: UIViewControllerRepresentable {
    @Binding var statusText: String
    func makeUIViewController(context: Context) -> WebKitShellViewController {
        let vc = WebKitShellViewController()
        vc.setStatusHandler { msg in
            Task { @MainActor in statusText = msg }
        }
        return vc
    }
    func updateUIViewController(_ uiViewController: WebKitShellViewController, context: Context) {}
}
