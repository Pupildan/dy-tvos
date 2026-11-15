import Foundation
import UIKit

/// v164 作品/合集 WebView 截获（用户拍板降维打击路线）。
/// 背景：本地算 a_bogus 死路（自签探针实锤 len=180 vs myDV 168，Node/QuickJS 同现 → JSCore 无解）。
/// 本类不算签名——离屏 WebView 以桌面 Chrome 身份加载作者主页，页面 JS 自己算 168 签名、自己发
/// aweme/post / series / mix，我们只拦现成 response body。
/// v164 关键修复（v163 零捕获根因）：改用 **WKUserContentController document-start 注入** hook
/// （DYCreateWebViewWithInject），page JS 跑之前就装好拦截器——v163 用 evaluateJavaScript 事后注入漏了首屏 XHR。
/// 铁律边界：离屏数据泵非 UI，从不挂视图层级（同 v161 cookie 引导性质）。
final class DYWorksCapture: NSObject {
    static let shared = DYWorksCapture()
    private var webView: UIView?
    private var pollTimer: Timer?
    private var deadlineTimer: Timer?
    private var scrollTimer: Timer?
    private var gotWorks = false
    private var pollCount = 0
    private var totalCap = 0
    private var rehooked = false

    /// document-start 注入的拦截器：命中作品/合集端点的响应体存 window.__dyCap
    private static let hookJS = """
    (function(){
      if(window.__dyHooked) return; window.__dyHooked=true; window.__dyCap=[]; window.__dyXHRTotal=0;
      function grab(u,b){ try{
        if(!u||!b) return;
        var s=String(u);
        if(s.indexOf('aweme/post')<0&&s.indexOf('series/')<0&&s.indexOf('mix/')<0&&s.indexOf('user/profile')<0) return;
        var body=(typeof b==='string')?b:JSON.stringify(b);
        window.__dyCap.push({u:s.slice(0,120),b:body.slice(0,60000)});
      }catch(e){} }
      var xo=XMLHttpRequest.prototype.open, xs=XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open=function(m,u){ this.__u=u; return xo.apply(this,arguments); };
      XMLHttpRequest.prototype.send=function(){ var x=this; window.__dyXHRTotal=(window.__dyXHRTotal||0)+1;
        this.addEventListener('readystatechange',function(){ if(x.readyState===4){ try{ var t=x.responseType; if(!t||t==='text'||t==='json'){ grab(x.__u,(t==='json')?x.response:x.responseText); } }catch(e){} } });
        return xs.apply(this,arguments); };
      var of=window.fetch;
      if(of){ window.fetch=function(){ var a=arguments,u=(a[0]&&a[0].url)||a[0]; window.__dyXHRTotal=(window.__dyXHRTotal||0)+1;
        return of.apply(this,arguments).then(function(r){ try{ var c=r.clone(); c.text().then(function(t){ grab(u,t); }).catch(function(){}); }catch(e){} return r; }); }; }
    })();
    """

    /// 抽回 __dyCap + 诊断透视（page 加载状态/当前 URL/hook 状态/页面 XHR 总数）
    private static let drainJS = """
    (function(){
      var cap=[]; try{ cap=window.__dyCap.splice(0); }catch(e){}
      var diag={rs:'',href:'',hooked:false,xhr:0,n:cap.length};
      try{ diag.rs=document.readyState; }catch(e){}
      try{ diag.href=String(location.href).slice(0,90); }catch(e){}
      try{ diag.hooked=!!window.__dyHooked; }catch(e){}
      try{ diag.xhr=window.__dyXHRTotal||0; }catch(e){}
      diag.cap=cap; return JSON.stringify(diag);
    })();
    """

    /// 拉取作者作品+合集（原型：只截获+日志，不接 UI）。secUid 空→忽略。
    func fetch(secUid: String) {
        guard !secUid.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.webView != nil { DYLog.shared.log("WORKSCAP busy,skip"); return }
            // document-start 注入 hook（page JS 之前装好，零漏首屏）
            guard let wv = DYCreateWebViewWithInject(CGRect(x: 0, y: 0, width: 1, height: 1), DYProfileClient.webUA, Self.hookJS) as? UIView else {
                DYLog.shared.event("WORKSCAP FAIL: 注入式 WKWebView 创建失败")
                return
            }
            self.webView = wv
            self.gotWorks = false
            self.totalCap = 0
            self.rehooked = false
            DYLog.shared.log("WORKSCAP load user page secUid=\(secUid.prefix(16))... (doc-start inject)")
            let url = "https://www.douyin.com/user/\(secUid)"
            wv.perform(NSSelectorFromString("loadRequest:"), with: NSURLRequest(url: URL(string: url)!))
            self.startPolling()
            self.deadlineTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
                DYLog.shared.log("WORKSCAP deadline")
                self?.drain(tag: "deadline")
                self?.teardown()
            }
            // 滚动触发懒加载（作品列表常滚动才发 aweme/post）
            self.scrollTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
                self?.scrollPage()
            }
        }
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

    private func drain(tag: String) {
        guard let wv = webView, !gotWorks else { return }
        evalJS(Self.drainJS, tag: tag) { [weak self] result in
            guard let self else { return }
            guard let json = result as? String, let data = json.data(using: .utf8),
                  let diag = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            let rs = diag["rs"] as? String ?? "?"
            let href = diag["href"] as? String ?? "?"
            let hooked = diag["hooked"] as? Bool ?? false
            let xhr = diag["xhr"] as? Int ?? 0
            let cap = diag["cap"] as? [[String: Any]] ?? []
            // 兜底：document-start 注入没生效(hooked=0)→ 用 evaluateJavaScript 补装 hook
            if !hooked, !self.rehooked {
                self.rehooked = true
                DYLog.shared.log("WORKSCAP[\(tag)] hooked=0 → evaluateJavaScript 补装 hook")
                self.evalJS(Self.hookJS, tag: "rehook")
            }
            // 诊断透视：每 3 次轮询打一条 page 状态
            if self.pollCount % 3 == 0 {
                DYLog.shared.log("WORKSCAP[\(tag)] page rs=\(rs) hooked=\(hooked ? 1 : 0) xhrTotal=\(xhr) cap=\(cap.count) href=\(href)")
            }
            for item in cap {
                let u = item["u"] as? String ?? "?"
                let b = item["b"] as? String ?? ""
                let kind = u.contains("aweme/post") ? "POST" : (u.contains("series/") ? "SERIES" : (u.contains("mix/") ? "MIX" : "PROFILE"))
                self.totalCap += 1
                DYLog.shared.event("WORKS CAP[\(tag)] \(kind) len=\(b.count) u=\(u)")
                if (kind == "POST" || kind == "SERIES" || kind == "MIX"), !b.isEmpty {
                    DYLog.shared.log("WORKS CAP BODY head: " + String(b.prefix(240)))
                    self.gotWorks = true
                }
            }
            if self.gotWorks {
                DYLog.shared.event("WORKS CAP OK total=\(self.totalCap) xhrTotal=\(xhr)——WebView 截获成立")
                self.teardown()
            }
        }
    }

    private func scrollPage() {
        guard let wv = webView else { return }
        evalJS("try{ window.scrollTo(0, document.body.scrollHeight); }catch(e){}; 's'", tag: "scroll")
    }

    private func evalJS(_ js: String, tag: String, done: ((Any?) -> Void)? = nil) {
        guard let wv = webView else { return }
        let handler: @convention(block) (NSObject?, NSObject?) -> Void = { result, error in
            if let error = error as? NSError {
                DYLog.shared.log("WORKSCAP[\(tag)] js err: \(error.localizedDescription)")
            }
            done?(result)
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
