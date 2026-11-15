import WebKit

/// 隐形 WebView cookie 引导（v160，用户拍板的解锁路径）。
/// 铁律边界说明：铁律禁的是"WebView 作为 UI"——本类**从不挂到任何视图层级**（1x1 离屏、
/// 不进 window），仅作为抖音首页 jsvmp 反爬挑战页的 JS 执行引擎，让挑战脚本自己算出
/// __ac_signature/s_v_web_id 等信任 cookie，随后从 WKHTTPCookieStore 收割并入
/// DYProfileClient 罐。性质与已批准的扫码登录路线一致：仅引导/登录用，零界面。
/// 解锁目标：作品列表(aweme/post)、合集内容(series 家族)所需的 s_v_web_id/odin_tt 信任 cookie。
final class DYWebViewBootstrap: NSObject, WKNavigationDelegate {
    static let shared = DYWebViewBootstrap()
    private var webView: WKWebView?
    private var doneHandler: (() -> Void)?
    private var harvested = false

    /// 完成引导（若已收割过直接回调）。主线程调用。
    func run(_ done: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.harvested { done(); return }
            self.doneHandler = done
            if self.webView == nil {
                let cfg = WKWebViewConfiguration()
                cfg.allowsInlineMediaPlayback = false
                let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 180), configuration: cfg)
                wv.navigationDelegate = self
                self.webView = wv
                // 15s 兜底：无论挑战是否完成，收割现有 cookie 后放行
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                    guard let self, !self.harvested else { return }
                    self.harvestNow(tag: "deadline")
                    self.finish()
                }
                DYLog.shared.log("WEBBOOT load douyin home (invisible webview)")
                wv.load(URLRequest(url: URL(string: "https://www.douyin.com/?recommend=1")!))
            } else {
                self.webView?.reload()
            }
        }
    }

    private func harvestNow(tag: String) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            let wanted = ["s_v_web_id", "uifid", "UIFID_TEMP", "odin_tt", "msToken", "ttwid", "__ac_signature", "__ac_nonce"]
            var got: [String] = []
            for c in cookies where wanted.contains(c.name) {
                DYProfileClient.shared.absorbCookie(name: c.name, value: c.value)
                got.append(c.name)
            }
            DYLog.shared.log("WEBBOOT[\(tag)] cookies=" + (got.isEmpty ? "无" : got.joined(separator: ",")))
            if got.contains("s_v_web_id") { self?.harvested = true }
        }
    }

    private func finish() {
        harvested = true
        doneHandler?()
        doneHandler = nil
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let u = webView.url?.absoluteString.prefix(70) ?? "?"
        DYLog.shared.log("WEBBOOT didFinish \(u)")
        // 挑战页算完签名会自刷新；didFinish+2s 与 +6s 各收一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.harvested else { return }
            self.harvestNow(tag: "didFinish+2")
            if self.harvested { self.finish() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, !self.harvested else { return }
            self.harvestNow(tag: "didFinish+6")
            if self.harvested { self.finish() }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        DYLog.shared.log("WEBBOOT didFail: \(error.localizedDescription)")
        harvestNow(tag: "fail")
        finish()
    }
}
