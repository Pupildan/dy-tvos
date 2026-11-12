import Foundation
import UIKit
import SwiftUI
import ObjectiveC.runtime

/// A 路线外壳：运行时实例化私有 WKWebView，加载抖音桌面版。
/// 编译期不依赖 WebKit 符号；可行性只能真机验证。
/// 焦点意图：本 VC 内无 Button，焦点落在 WKWebView 或无目标；登录走手机扫码，不依赖遥控器操作网页。
final class WebKitShellViewController: UIViewController {
    private var status: ((String) -> Void)?
    private static var bridgeKey: UInt8 = 0

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

        // configuration.customUserAgent = desktopUA (KVC, 运行时)
        let config = (ConfigCls as NSObject.Type).alloc()
        config.perform(NSSelectorFromString("init"))
        config.setValue(WebKitShellViewController.desktopUA, forKey: "customUserAgent")

        let navBar = UILabel()
        navBar.text = "douyin.com (desktop UA)"
        navBar.textColor = .black
        navBar.font = .systemFont(ofSize: 20, weight: .semibold)
        navBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navBar)

        let wvObj = (WKWebViewCls as NSObject.Type).alloc()
        wvObj.perform(NSSelectorFromString("initWithFrame:configuration:"),
                      with: NSValue(cgRect: .zero), with: config)
        guard let wvView = wvObj as? UIView else {
            status?("FAIL: WKWebView 实例无法转为 UIView")
            return
        }
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

        // 挂 navigation delegate 桥（运行时）
        let bridge = WebKitNavBridge()
        bridge.onEvent = { [weak self] msg in self?.status?(msg) }
        wvView.setValue(bridge, forKey: "navigationDelegate")
        objc_setAssociatedObject(wvView, &WebKitShellViewController.bridgeKey, bridge,
                                 .OBJC_ASSOCIATION_RETAIN)

        // 加载抖音桌面版首页（应弹扫码登录）
        let url = URL(string: "https://www.douyin.com/")!
        wvView.perform(NSSelectorFromString("loadRequest:"), with: NSURLRequest(url: url))
        status?("loading douyin.com ...")
    }
}

/// 运行时桥接 WKNavigationDelegate：靠 ObjC 消息转发接收回调，不声明 WebKit 协议。
final class WebKitNavBridge: NSObject {
    var onEvent: ((String) -> Void)?
    private static let knownSelectors: [Selector] = [
        NSSelectorFromString("webView:didCommitNavigation:"),
        NSSelectorFromString("webView:didFinishNavigation:"),
        NSSelectorFromString("webView:didFailNavigation:withError:"),
        NSSelectorFromString("webView:didFailProvisionalNavigation:withError:"),
    ]

    override func responds(to aSelector: Selector!) -> Bool {
        if WebKitNavBridge.knownSelectors.contains(aSelector) { return true }
        return super.responds(to: aSelector)
    }

    override func methodSignature(for selector: Selector!) -> NSMethodSignature! {
        if super.responds(to: selector) { return super.methodSignature(for: selector) }
        // 伪造 (webView, navigation[, error]) 签名
        return NSMethodSignature.signature(withObjCTypes: "v@:@@@")
    }

    override func forwardInvocation(_ invocation: NSInvocation!) {
        guard let sel = invocation?.selector else { return }
        switch NSStringFromSelector(sel) {
        case "webView:didCommitNavigation:":
            onEvent?("commit: 开始加载")
        case "webView:didFinishNavigation:":
            onEvent?("finish: 加载完成 (二维码应已显示, 手机扫码登录)")
        case "webView:didFailNavigation:withError:",
             "webView:didFailProvisionalNavigation:withError:":
            onEvent?("fail: 加载失败")
        default:
            super.forwardInvocation(invocation)
        }
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
