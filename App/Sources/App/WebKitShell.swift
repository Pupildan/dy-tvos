import Foundation
import UIKit
import SwiftUI
import ObjectiveC.runtime

/// 运行时动态构建极简 ObjC 类充当 WKNavigationDelegate（空实现，仅让 respondsToSelector 通过）。
/// 抓链接靠 fetch hook + scriptMessageHandler，不经此 delegate。
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
        return (cls as! NSObject.Type).init()
    }
}

/// P2 探测外壳：隐藏式 WebView 加载抖音桌面版，注入 fetch/XHR hook 抓 Feed API 视频直链。
/// 目标：确认抖音是 API 下发直链（.mp4/.m3u8）还是纯 Blob 分片。
/// 焦点意图：本屏无 Button；抓到的链接用纯 Text 展示（不可聚焦），遥控器焦点不会被劫持。
final class WebKitShellViewController: UIViewController {
    private var status: ((String) -> Void)?
    private var pollTimer: Timer?
    private var lastLoading = false
    private weak var webView: UIView?
    private static var delegateKey: UInt8 = 0

    static let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private var captured: [String] = []
    private var seen = Set<String>()
    private var loggedFirstVideo = false
    private var sawReqs = false
    private var tick = 0

    func setStatusHandler(_ handler: @escaping (String) -> Void) {
        status = handler
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        DYLog.shared.log("SHELL viewDidLoad")

        // WebView 缩小置底（probe 阶段仍渲染以便抖音自己跑 JS，但不占主视觉）
        guard let wvView = DYCreateWebViewWithFrame(CGRect(x: 0, y: 0, width: 400, height: 225),
                                                    WebKitShellViewController.desktopUA) as? UIView else {
            status?("FAIL: 无法加载私有 WebKit / WKWebView")
            DYLog.shared.log("SHELL FAIL: create webview returned nil")
            return
        }
        DYLog.shared.log("SHELL webview created OK")
        webView = wvView
        wvView.translatesAutoresizingMaskIntoConstraints = false
        wvView.alpha = 0.35 // 探测期半透明，确认它在跑但不抢焦点
        view.addSubview(wvView)
        NSLayoutConstraint.activate([
            wvView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            wvView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            wvView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            wvView.heightAnchor.constraint(equalToConstant: 225),
        ])

        let delegate = WebKitDelegateFactory.makeDelegate()
        wvView.setValue(delegate, forKey: "navigationDelegate")
        objc_setAssociatedObject(wvView, &WebKitShellViewController.delegateKey, delegate,
                                 .OBJC_ASSOCIATION_RETAIN)

        // 注入 fetch/XHR hook（documentStart），抓 Feed API 里的视频直链
        DYInstallFetchHook(wvView)

        let url = URL(string: "https://www.douyin.com/")!
        wvView.perform(NSSelectorFromString("loadRequest:"), with: NSURLRequest(url: url))
        status?("loading + hooking douyin.com ...")

        startPolling()
    }

    private func startPolling() {
        lastLoading = false
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            // 消费 hook 回传的最新一条（可能是批量：REQS/VIDEOS 多行）
            if let msg = DYLastHookMessage() {
                DYClearHookMessage()
                if msg == "HOOK_INSTALLED" {
                    DYLog.shared.log("HOOK installed, awaiting feed API")
                    self.status?("hook installed, waiting for feed API ...")
                } else if msg.hasPrefix("REQS\n") {
                    // 方向 A：抖音实际发起的请求 URL 批量，逐行进收集器日志
                    let lines = msg.split(separator: "\n").dropFirst()
                    DYLog.shared.log("REQS batch(\(lines.count)):")
                    for l in lines { DYLog.shared.log("  \(l)") }
                    if !self.sawReqs { self.sawReqs = true; self.status?("捕获到 \(lines.count) 个请求 URL，看收集器日志") }
                } else if msg.hasPrefix("VIDEOS\n") {
                    let lines = msg.split(separator: "\n").dropFirst()
                    DYLog.shared.log("VIDEOS batch(\(lines.count)):")
                    for l in lines {
                        DYLog.shared.log("  \(l)")
                        if !self.seen.contains(String(l)) {
                            self.seen.insert(String(l))
                            self.captured.insert(String(l), at: 0)
                        }
                    }
                    if self.captured.count > 40 { self.captured.removeLast(self.captured.count - 40) }
                    if !self.loggedFirstVideo {
                        self.loggedFirstVideo = true
                        self.status?(self.summary())
                    }
                }
            }
            // 每 ~2s 打一次运行计数（0.4s×5）
            self.tick += 1
            if self.tick % 5 == 0 {
                let vids = self.captured.filter { $0.contains(".mp4") || $0.contains(".m3u8") || $0.contains("douyinvod") }
                DYLog.shared.log("STAT captured=\(self.captured.count) videoLinks=\(vids.count)")
            }
        }
    }

    private func summary() -> String {
        let n = captured.count
        let head = captured.prefix(6).joined(separator: "\n")
        return "捕获视频直链 \(n) 条 (P2 可行: API 下发直链)\n---\n\(head)"
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
