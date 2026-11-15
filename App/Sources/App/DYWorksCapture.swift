import Foundation
import UIKit

/// v166 作品/合集 WebView 截获（用户拍板降维打击路线）——**已接 UI**。
/// 背景：本地算 a_bogus 死路（自签探针实锤 len=180 vs myDV 168，Node/QuickJS 同现 → JSCore 无解）；
/// 原生 fetch 资料链也被服务端 200 空拒（v165 真机日志实锤 PROFILE fetch fail len=0）。
/// 本类不算签名——离屏 WebView 以桌面 Chrome 身份加载作者主页，页面 JS 自己算 168 签名、自己发
/// profile/aweme-post/series/mix，我们只拦现成 response body、解析成模型、经 delegate 喂 UI。
/// v165 真机已验证截获成立（WORKS CAP POST len=60000 aweme_list has_more=1）。
/// v166：body 上限 60000→300000（60KB 是日志截断，真作品 JSON 约 212KB，截断解析会失败）。
/// 铁律边界：离屏数据泵非 UI，从不挂视图层级（同 v161 cookie 引导性质）。
final class DYWorksCapture: NSObject {
    static let shared = DYWorksCapture()

    /// UI 订阅截获结果（DYProfileScreen 注册；回调已在主线程）。
    /// 注意：DYProfileScreen 是 struct（SwiftUI View），协议不能加 :AnyObject 约束（struct 无法遵循 class 协议）。
    /// delegate 也用 strong（struct 非 weak 目标；DYWorksCapture 单例 + View 生命周期内注册，无循环引用）。
    protocol Delegate {
        func worksCaptureDidCapture(profile: DYProfileUser)
    }
    var delegate: Delegate?

    private var webView: UIView?
    private var pollTimer: Timer?
    private var deadlineTimer: Timer?
    private var scrollTimer: Timer?
    private var gotWorks = false
    private var gotProfile = false
    private var pollCount = 0
    private var totalCap = 0
    private var rehooked = false
    private var currentSecUid = ""

    /// document-start 注入的拦截器：命中资料/作品/合集端点的响应体存 window.__dyCap
    private static let hookJS = """
    (function(){
      if(window.__dyHooked) return; window.__dyHooked=true; window.__dyCap=[]; window.__dyXHRTotal=0;
      function grab(u,b){ try{
        if(!u||!b) return;
        var s=String(u);
        if(s.indexOf('aweme/post')<0&&s.indexOf('series/')<0&&s.indexOf('mix/')<0&&s.indexOf('user/profile')<0) return;
        var body=(typeof b==='string')?b:JSON.stringify(b);
        window.__dyCap.push({u:s.slice(0,120),b:body.slice(0,300000)});
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

    /// 抽回 __dyCap + 诊断透视
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

    /// 拉取作者资料+作品（截获→解析→delegate 喂 UI）。secUid 空→忽略。
    func fetch(secUid: String) {
        guard !secUid.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.webView != nil { DYLog.shared.log("WORKSCAP busy,skip"); return }
            guard let wv = DYCreateWebViewWithInject(CGRect(x: 0, y: 0, width: 1, height: 1), DYProfileClient.webUA, Self.hookJS) as? UIView else {
                DYLog.shared.event("WORKSCAP FAIL: 注入式 WKWebView 创建失败")
                return
            }
            self.webView = wv
            self.gotWorks = false
            self.gotProfile = false
            self.totalCap = 0
            self.rehooked = false
            self.currentSecUid = secUid
            DYLog.shared.log("WORKSCAP load user page secUid=\(secUid.prefix(16))... (doc-start inject)")
            let url = "https://www.douyin.com/user/\(secUid)"
            wv.perform(NSSelectorFromString("loadRequest:"), with: NSURLRequest(url: URL(string: url)!))
            self.startPolling()
            self.deadlineTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
                DYLog.shared.log("WORKSCAP deadline")
                self?.drain(tag: "deadline")
                self?.teardown()
            }
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
        guard let wv = webView else { return }
        // 资料+作品都拿到即可收尾（不必等全部懒加载）
        if gotWorks && gotProfile { teardown(); return }
        evalJS(Self.drainJS, tag: tag) { [weak self] result in
            guard let self else { return }
            guard let json = result as? String, let data = json.data(using: .utf8),
                  let diag = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            let hooked = diag["hooked"] as? Bool ?? false
            let cap = diag["cap"] as? [[String: Any]] ?? []
            if !hooked, !self.rehooked {
                self.rehooked = true
                DYLog.shared.log("WORKSCAP[\(tag)] hooked=0 → evaluateJavaScript 补装 hook")
                self.evalJS(Self.hookJS, tag: "rehook")
            }
            for item in cap {
                let u = item["u"] as? String ?? "?"
                let b = item["b"] as? String ?? ""
                self.totalCap += 1
                if u.contains("user/profile"), !self.gotProfile {
                    self.gotProfile = true
                    DYLog.shared.event("WORKS CAP PROFILE len=\(b.count)")
                    self.handleProfile(b)
                } else if u.contains("aweme/post"), !b.isEmpty {
                    DYLog.shared.event("WORKS CAP POST len=\(b.count)")
                    self.handleWorks(b)
                } else if u.contains("series/") || u.contains("mix/") {
                    DYLog.shared.event("WORKS CAP SERIES/MIX len=\(b.count)")
                }
            }
            if self.gotWorks && self.gotProfile {
                DYLog.shared.event("WORKS CAP OK total=\(self.totalCap)——资料+作品截获成立,喂UI")
                self.teardown()
            }
        }
    }

    /// 解析 profile/other 响应 → DYProfileUser → delegate
    private func handleProfile(_ body: String) {
        guard let d = body.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              (obj["status_code"] as? Int ?? -1) == 0,
              let user = obj["user"] as? [String: Any] else {
            DYLog.shared.log("WORKSCAP profile parse fail")
            return
        }
        var avatar = ""
        if let at = user["avatar_thumb"] as? [String: Any], let ul = at["url_list"] as? [String] {
            avatar = ul.first(where: { $0.hasPrefix("http") }) ?? ""
        }
        let u = DYProfileUser(
            nickname: user["nickname"] as? String ?? "",
            avatarUrl: avatar,
            secUid: user["sec_uid"] as? String ?? currentSecUid,
            signature: user["signature"] as? String ?? "",
            followerCount: (user["follower_count"] as? NSNumber)?.intValue ?? 0,
            followingCount: (user["following_count"] as? NSNumber)?.intValue ?? 0,
            awemeCount: (user["aweme_count"] as? NSNumber)?.intValue ?? 0,
            totalFavorited: (user["total_favorited"] as? NSNumber)?.intValue ?? 0
        )
        DYLog.shared.event("WORKSCAP profile ok nick=\(u.nickname) fans=\(u.followerCount) works=\(u.awemeCount)")
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.worksCaptureDidCapture(profile: u)
        }
    }

    /// 解析 aweme/post 响应 → 记录作品数（v166 先接资料+计数，作品网格待下版本）
    private func handleWorks(_ body: String) {
        guard let d = body.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              (obj["status_code"] as? Int ?? -1) == 0 else {
            DYLog.shared.log("WORKSCAP works parse fail")
            return
        }
        let list = (obj["aweme_list"] as? [[String: Any]]) ?? []
        let hasMore = (obj["has_more"] as? Int ?? 0)
        DYLog.shared.event("WORKSCAP works ok n=\(list.count) hasMore=\(hasMore)")
        gotWorks = true
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
