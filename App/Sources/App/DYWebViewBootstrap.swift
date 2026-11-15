import Foundation
import UIKit

/// 隐形 WebView cookie 引导（v161，用户拍板的解锁路径）。
/// 铁律边界说明：铁律禁的是"WebView 作为 UI"——本类**从不挂到任何视图层级**（1x1 离屏、
/// 不进 window），仅作为抖音首页 jsvmp 反爬挑战页的 JS 执行引擎，让挑战脚本自己算出
/// __ac_signature/s_v_web_id 等信任 cookie，再经 document.cookie 收割进 DYProfileClient 罐。
/// 性质与已批准的扫码登录路线一致：仅引导/登录用，零界面。
///
/// 实现：tvOS 无公开 WebKit 模块（v160 CI 实锤 unable to resolve 'WebKit'）——
/// 照抄 v2-v8 已真机验证的方案：DYWebViewShim.m dlopen 私有 WebKit.framework +
/// objc_msgSend 创建 WKWebView（桥接头暴露 DYCreateWebViewWithFrame）。
/// 轮询 isLoading（v3-v8 同款，避开 ObjC delegate 类），加载完 evaluateJavaScript
/// "document.cookie" 收割非 HttpOnly 信任 cookie（s_v_web_id/__ac_signature/uifid…）。
final class DYWebViewBootstrap: NSObject {
    static let shared = DYWebViewBootstrap()
    private var webView: UIView?
    private var doneHandler: (() -> Void)?
    private var pollTimer: Timer?
    private var deadlineTimer: Timer?
    private var settledCount = 0
    private var retryCount = 0
    private var harvested = false

    /// 完成引导（已成功过则直接回调）。
    func run(_ done: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.harvested { done(); return }
            self.doneHandler = done
            if self.webView == nil {
                // 私有 WebKit 创建（dlopen + objc_msgSend，v7/v8 真机验证过）
                let ua = DYProfileClient.webUA
                guard let wv = DYCreateWebViewWithFrame(CGRect(x: 0, y: 0, width: 1, height: 1), ua) as? UIView else {
                    DYLog.shared.event("WEBBOOT FAIL: 私有 WKWebView 创建失败（dlopen WebKit）")
                    done(); return
                }
                self.webView = wv
                // 20s 兜底超时：收割现有 cookie 后放行（不阻塞资料链）
                self.deadlineTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
                    DYLog.shared.log("WEBBOOT deadline 兜底收割")
                    self?.harvestNow(tag: "deadline")
                    self?.finish()
                }
                DYLog.shared.log("WEBBOOT load douyin home (invisible shim webview)")
                let req = URLRequest(url: URL(string: "https://www.douyin.com/?recommend=1")!)
                wv.perform(NSSelectorFromString("loadRequest:"), with: NSURLRequest(url: req.url!))
                self.startPolling()
            } else {
                self.webView?.perform(NSSelectorFromString("reload"))
                self.startPolling()
            }
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        settledCount = 0
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let wv = self.webView else { return }
            let loading = (wv.value(forKey: "isLoading") as? Bool) ?? true
            if !loading {
                self.settledCount += 1
                // 页面加载完且稳定 1s（挑战 JS 可能自刷新，刷新会重新 loading）
                if self.settledCount >= 2 {
                    self.pollTimer?.invalidate()
                    self.pollTimer = nil
                    self.harvestViaJS(tag: "settled")
                }
            } else {
                self.settledCount = 0
            }
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    /// evaluateJavaScript "document.cookie" → 解析 k=v; 对 → 并罐（非 HttpOnly 才可见，
    /// s_v_web_id/__ac_signature/uifid 均 JS 可见；ttwid/odin_tt HttpOnly 由既有链路覆盖）。
    private func harvestViaJS(tag: String) {
        guard let wv = webView else { return }
        let handler: @convention(block) (NSObject?, NSObject?) -> Void = { [weak self] result, error in
            guard let self else { return }
            if let error = error as? NSError {
                DYLog.shared.log("WEBBOOT[\(tag)] js err: \(error.localizedDescription)")
            } else if let cookieStr = result as? String {
                var got: [String] = []
                for pair in cookieStr.components(separatedBy: "; ") {
                    let kv = pair.components(separatedBy: "=")
                    if kv.count >= 2, !kv[0].isEmpty, !kv[1].isEmpty {
                        let name = kv[0]
                        let value = kv.dropFirst(1).joined(separator: "=")
                        if ["s_v_web_id", "uifid", "UIFID_TEMP", "__ac_signature", "__ac_nonce", "odin_tt", "msToken"].contains(name) {
                            DYProfileClient.shared.absorbCookie(name: name, value: value)
                            got.append(name)
                        }
                    }
                }
                DYLog.shared.log("WEBBOOT[\(tag)] document.cookie=" + (got.isEmpty ? "无目标 cookie" : got.joined(separator: ",")))
                if got.contains("s_v_web_id") || got.contains("__ac_signature") {
                    self.harvested = true
                    self.finish()
                } else {
                    // 挑战 JS 尚未完成：2s 后再收一次（挑战页自刷新会重置稳定计数重走 settled）
                    self.retryCount += 1
                    if self.retryCount < 6 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                            self?.harvestViaJS(tag: "retry\(self?.retryCount ?? 0)")
                        }
                    }
                }
            }
        }
        let block = unsafeBitCast(handler, to: AnyObject.self)
        wv.perform(NSSelectorFromString("evaluateJavaScript:completionHandler:"),
                   with: "document.cookie",
                   with: block)
    }

    private func finish() {
        harvested = true
        pollTimer?.invalidate()
        pollTimer = nil
        deadlineTimer?.invalidate()
        deadlineTimer = nil
        doneHandler?()
        doneHandler = nil
    }
}
