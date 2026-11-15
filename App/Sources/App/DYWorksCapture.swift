import Foundation
import UIKit

/// v163 作品列表 WebView 截获原型（用户拍板的降维打击路线）。
/// 背景：本地算 a_bogus 死路（自签探针实锤 len=180 vs myDV 168，Node/QuickJS 同现 → JSCore 无解）。
/// 本类不再算签名——让隐藏 WebView 自己以桌面 Chrome 身份加载作者主页，页面 JS 自己算出 168 签名、
/// 自己发出 aweme/post，我们只拦现成的 response body。
/// 铁律边界：铁律禁"WebView 作为 UI"——本类离屏、从不挂视图层级，仅作数据泵（同 v161 cookie 引导性质）。
///
/// 机制（零新 ObjC，复用 v161 已真机验证的 evaluateJavaScript 通道）：
///   导航作者页 → 注入 XHR/fetch 覆写把 aweme/post 响应体塞进 window.__dyCap →
///   轮询 evaluateJavaScript 抽回 → DYLog 全量日志（WORKS CAP）。
/// 验证目标：真机日志出现 WORKS CAP hit body>0 = 截获成立，整套方案立住。
final class DYWorksCapture: NSObject {
    static let shared = DYWorksCapture()
    private var webView: UIView?
    private var pollTimer: Timer?
    private var deadlineTimer: Timer?
    private var scrollTimer: Timer?
    private var gotWorks = false
    private var pollCount = 0

    /// 拉取作者作品（原型：只截获+日志，不接 UI）。secUid 空→忽略。
    func fetch(secUid: String) {
        guard !secUid.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.webView != nil { return }   // 原型：一次一个，进行中忽略
            guard let wv = DYCreateWebViewWithFrame(CGRect(x: 0, y: 0, width: 1, height: 1), DYProfileClient.webUA) as? UIView else {
                DYLog.shared.event("WORKSCAP FAIL: 私有 WKWebView 创建失败")
                return
            }
            self.webView = wv
            DYLog.shared.log("WORKSCAP load user page secUid=\(secUid.prefix(16))...")
            let url = "https://www.douyin.com/user/\(secUid)"
            wv.perform(NSSelectorFromString("loadRequest:"), with: NSURLRequest(url: URL(string: url)!))
            self.installHook()
            self.startPolling()
            // 18s 兜底收尾
            self.deadlineTimer = Timer.scheduledTimer(withTimeInterval: 18, repeats: false) { [weak self] _ in
                DYLog.shared.log("WORKSCAP deadline")
                self?.drain(tag: "deadline")
                self?.teardown()
            }
            // 4s 后尝试滚动触发懒加载（作品列表常滚动才发 aweme/post）
            self.scrollTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
                self?.scrollPage()
            }
        }
    }

    /// 注入 XHR/fetch 覆写：命中 aweme/post 的响应体存 window.__dyCap
    private func installHook() {
        guard let wv = webView else { return }
        let js = """
        (function(){
          if(window.__dyHooked) return; window.__dyHooked=true; window.__dyCap=[];
          function grab(u,b){ try{ if(u&&u.indexOf('aweme/post')>=0&&b){ window.__dyCap.push({u:String(u).slice(0,90),b:(typeof b==='string'?b:JSON.stringify(b)).slice(0,40000)}); } }catch(e){} }
          var xo=XMLHttpRequest.prototype.open, xs=XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open=function(m,u){ this.__u=u; return xo.apply(this,arguments); };
          XMLHttpRequest.prototype.send=function(){ this.addEventListener('readystatechange',function(){ if(this.readyState===4){ try{ var t=this.responseType; if(!t||t==='text'){ grab(this.__u,this.responseText); } }catch(e){} } }); return xs.apply(this,arguments); };
          var of=window.fetch;
          if(of){ window.fetch=function(){ var a=arguments,u=(a[0]&&a[0].url)||a[0]; return of.apply(this,arguments).then(function(r){ try{ var c=r.clone(); c.text().then(function(t){ grab(u,t); }).catch(function(){}); }catch(e){} return r; }); }; }
        })();
        """
        evalJS(js, tag: "hook")
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollCount = 0
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pollCount += 1
            self.drain(tag: "p\(self.pollCount)")
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    /// 抽回 window.__dyCap（splice 清空），逐条日志
    private func drain(tag: String) {
        guard let wv = webView, !gotWorks else { return }
        evalJS("try{ JSON.stringify(window.__dyCap.splice(0)) }catch(e){ '[]' }", tag: "drain\(tag)") { [weak self] result in
            guard let self else { return }
            guard let json = result as? String, let data = json.data(using: .utf8),
                  let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]], !arr.isEmpty else {
                return
            }
            for item in arr {
                let u = item["u"] as? String ?? "?"
                let b = item["b"] as? String ?? ""
                let isPost = u.contains("aweme/post")
                DYLog.shared.event("WORKS CAP[\(tag)] \(isPost ? "POST" : "other") len=\(b.count) u=\(u)")
                if isPost, !b.isEmpty {
                    DYLog.shared.log("WORKS CAP BODY head: " + String(b.prefix(200)))
                    self.gotWorks = true
                }
            }
            if self.gotWorks {
                DYLog.shared.event("WORKS CAP OK——WebView 截获 aweme/post 响应成立")
                self.teardown()
            }
        }
    }

    private func scrollPage() {
        guard let wv = webView else { return }
        evalJS("window.scrollTo(0, document.body.scrollHeight); 'scrolled'", tag: "scroll")
    }

    /// evaluateJavaScript（v161 同款 ObjC block 桥）
    private func evalJS(_ js: String, tag: String, done: ((Any?) -> Void)? = nil) {
        guard let wv = webView else { return }
        let handler: @convention(block) (NSObject?, NSObject?) -> Void = { [weak self] result, error in
            if let error = error as? NSError {
                DYLog.shared.log("WORKSCAP[\(tag)] js err: \(error.localizedDescription)")
            }
            done?(result)
            _ = self
        }
        let block = unsafeBitCast(handler, to: AnyObject.self)
        wv.perform(NSSelectorFromString("evaluateJavaScript:completionHandler:"), with: js, with: block)
    }

    private func teardown() {
        pollTimer?.invalidate(); pollTimer = nil
        deadlineTimer?.invalidate(); deadlineTimer = nil
        scrollTimer?.invalidate(); scrollTimer = nil
        webView = nil
    }
}
