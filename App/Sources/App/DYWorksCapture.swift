import Foundation
import UIKit

/// v168 截获的单条作品（JS 端预解析精简后传回——绕开大 JSON 截断）。
/// 字段路径与 DYFeedClient.parseWeb 同构（aweme/post 响应=同款 web JSON）。
struct DYCapturedWork {
    let id: String
    let desc: String
    let coverUrl: String
    /// 候选播放直链（play_addr→play_addr_265→download_addr 合并，'|' join；播放时 selectBestPlayUrl 选链）
    let playUrls: [String]
    let durationMs: Int
    let isImages: Bool
    let createTime: Int
    /// 合集名（aweme/post 的 mix_info.mix_name；空=非合集）
    let mixName: String
    /// v172 合集 id（mix_info.mix_id）——合集屏数据钥匙
    let mixId: String
    /// v172 右轨统计（赞/评/藏/享）——v171 真机实锤作品播放右轨全是 0
    let digg: Int
    let comment: Int
    let collect: Int
    let share: Int
}

/// v166+ 作品/合集 WebView 截获（用户拍板降维打击路线）——已接 UI。
/// 背景：本地算 a_bogus 死路（自签探针实锤 len=180 vs myDV 168 → JSCore 无解）；
/// 原生 fetch 资料链也被服务端 200 空拒（v165 真机日志实锤 PROFILE fetch fail len=0）。
/// 本类不算签名——离屏 WebView 以桌面 Chrome 身份加载作者主页，页面 JS 自己算 168 签名、自己发
/// profile/aweme-post/series/mix，我们只拦现成 response body、解析成模型、经 delegate 喂 UI。
/// v167 真机验证：资料 100% 通（fans/works 真实数字，136 万粉大 V 也通）。
/// v168：aweme/post 改 **JS 端预解析精简**（v167 的 300KB 截断 parse fail 根因——JS slice 上限
/// 切残大 JSON；现在 JS 端直接 JSON.parse 只传 id/desc/cover/直链/duration，体积 300KB+→~10KB）。
/// 铁律边界：离屏数据泵非 UI，从不挂视图层级（同 v161 cookie 引导性质）。
final class DYWorksCapture: NSObject {
    static let shared = DYWorksCapture()

    /// UI 订阅截获结果（DYProfileScreen 注册；回调已在主线程）。
    /// 注意：DYProfileScreen 是 struct（SwiftUI View），协议不能加 :AnyObject 约束（struct 无法遵循 class 协议）。
    /// delegate 也用 strong（struct 非 weak 目标；DYWorksCapture 单例 + View 生命周期内注册，无循环引用）。
    protocol Delegate {
        func worksCaptureDidCapture(profile: DYProfileUser)
        func worksCaptureDidCapture(works: [DYCapturedWork], hasMore: Bool)
        /// v172 合集内容截获完成（mix/aweme 页面上下文 fetch → hook 拦截 → 精简解析）
        func worksCaptureDidCapture(mixWorks: [DYCapturedWork], mixId: String, mixName: String)
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
    /// v170 累积作品（v169 真机实锤：首批到手就 teardown → 只有一页，"自动加载剩余作品"从未生效）。
    /// 多批 aweme/post 按 id 去重合并，持续喂 delegate；增长停滞 15s 或 60s deadline 才收摊。
    private var capturedWorks: [DYCapturedWork] = []
    private var capturedHasMore = false
    private var firstBatchFed = false
    private var lastGrowthAt = Date()
    /// v172 会话模式：profile=作者资料+作品；mix=合集内容（页面上下文 fetch mix/aweme）
    private enum CapMode { case profile, mix }
    private var mode: CapMode = .profile
    private var pendingMixId = ""
    private var mixRequested = false

    /// document-start 注入的拦截器：命中资料/作品/合集端点的响应体存 window.__dyCap。
    /// aweme/post 响应在 JS 端预解析精简（每条只取 id/desc/cover/直链/duration/图集位）。
    private static let hookJS = """
    (function(){
      if(window.__dyHooked) return; window.__dyHooked=true; window.__dyCap=[]; window.__dyXHRTotal=0;
      function grab(u,b){ try{
        if(!u||!b) return;
        var s=String(u);
        if(s.indexOf('aweme/post')<0&&s.indexOf('series/')<0&&s.indexOf('mix/')<0&&s.indexOf('user/profile')<0) return;
        var body=(typeof b==='string')?b:JSON.stringify(b);
        if(s.indexOf('aweme/post')>=0||s.indexOf('mix/aweme')>=0){
          var j=null; try{ j=JSON.parse(body); }catch(e){}
          if(j&&(j.aweme_list)){
            var slim=[];
            for(var i=0;i<j.aweme_list.length;i++){
              var a=j.aweme_list[i]||{}; var v=a.video||{};
              var cand=[];
              if(v.play_addr&&v.play_addr.url_list)cand=cand.concat(v.play_addr.url_list);
              if(v.play_addr_265&&v.play_addr_265.url_list)cand=cand.concat(v.play_addr_265.url_list);
              if(v.download_addr&&v.download_addr.url_list)cand=cand.concat(v.download_addr.url_list);
              var cov='';
              if(v.cover&&v.cover.url_list&&v.cover.url_list[0])cov=v.cover.url_list[0];
              else if(v.origin_cover&&v.origin_cover.url_list&&v.origin_cover.url_list[0])cov=v.origin_cover.url_list[0];
              var mx=''; if(a.mix_info&&a.mix_info.mix_name)mx=a.mix_info.mix_name;
              var mxid=''; if(a.mix_info&&a.mix_info.mix_id)mxid=String(a.mix_info.mix_id);
              var st=[0,0,0,0];
              if(a.statistics){st=[a.statistics.digg_count||0,a.statistics.comment_count||0,a.statistics.collect_count||0,a.statistics.share_count||0];}
              slim.push({id:a.aweme_id||'',desc:a.desc||'',cov:cov,dur:v.duration||0,ct:a.create_time||0,mx:mx,mxid:mxid,
                st:st.join(','),imgs:(a.images&&a.images.length)?1:0,u:cand.join('|')});
            }
            var mn=''; if(j.mix_info&&j.mix_info.mix_name)mn=j.mix_info.mix_name;
            window.__dyCap.push({u:s.slice(0,120),b:JSON.stringify({works:slim,hasMore:(j.has_more||0),maxCursor:(j.max_cursor||0),mixName:mn})});
            return;
          }
        }
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
            if self.webView != nil {
                if self.mode == .profile, self.currentSecUid == secUid {
                    // 同作者重复触发（onChange 双 fire / 主页屏重开）：静默去重，
                    // 但把已累积的作品补发给新注册的 delegate（重开屏实例是新的，state 是空的）
                    let works = self.capturedWorks
                    let more = self.capturedHasMore
                    if !works.isEmpty {
                        DispatchQueue.main.async { [weak self] in
                            self?.delegate?.worksCaptureDidCapture(works: works, hasMore: more)
                        }
                    }
                    return
                }
                DYLog.shared.log("WORKSCAP switch author, restart capture")
                self.teardown()                                // 换作者：停旧会话重开
            }
            guard let wv = DYCreateWebViewWithInject(CGRect(x: 0, y: 0, width: 1, height: 1), DYProfileClient.webUA, Self.hookJS) as? UIView else {
                DYLog.shared.event("WORKSCAP FAIL: 注入式 WKWebView 创建失败")
                return
            }
            self.webView = wv
            self.mode = .profile
            self.gotWorks = false
            self.gotProfile = false
            self.totalCap = 0
            self.rehooked = false
            self.currentSecUid = secUid
            self.capturedWorks = []
            self.capturedHasMore = false
            self.firstBatchFed = false
            self.lastGrowthAt = Date()
            DYLog.shared.log("WORKSCAP load user page secUid=\(secUid.prefix(16))... (doc-start inject)")
            let url = "https://www.douyin.com/user/\(secUid)"
            wv.perform(NSSelectorFromString("loadRequest:"), with: NSURLRequest(url: URL(string: url)!))
            self.startPolling()
            self.deadlineTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
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
        guard webView != nil else { return }
        // v170：不再"首批即收摊"——持续滚动作者页加载更多作品；
        // 退出条件=增长停滞（已有作品 15s / 首批未到 25s）或 60s deadline。
        if mode == .profile {
            let settleGap: TimeInterval = gotWorks ? 15 : 25
            if gotProfile, Date().timeIntervalSince(lastGrowthAt) > settleGap {
                DYLog.shared.event("WORKSCAP settle (no growth \(Int(settleGap))s) total=\(self.capturedWorks.count)")
                self.teardown()
                return
            }
        } else if mixRequested, Date().timeIntervalSince(lastGrowthAt) > 15 {
            DYLog.shared.event("MIXCAP settle no-response mixId=\(pendingMixId)")
            self.teardown()
            return
        }
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
            // v172 mix 模式：页面加载完成 + hook 就位 → 页面上下文发 mix/aweme fetch（吃页面自己的签名包装）
            if self.mode == .mix, !self.mixRequested, hooked, (diag["rs"] as? String) == "complete" {
                self.mixRequested = true
                self.lastGrowthAt = Date()
                DYLog.shared.log("MIXCAP page ready → fetch mix/aweme mixId=\(self.pendingMixId)")
                let js = Self.mixFetchJS(mixId: self.pendingMixId)
                self.evalJS(js, tag: "mixfetch")
            }
            for item in cap {
                let u = item["u"] as? String ?? "?"
                let b = item["b"] as? String ?? ""
                self.totalCap += 1
                if self.mode == .mix {
                    if u.contains("mix/aweme") {
                        DYLog.shared.event("MIXCAP response len=\(b.count) u=\(u.prefix(80))")
                        self.handleMix(b)
                    }
                    continue
                }
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
            if self.mode == .profile, self.gotWorks && self.gotProfile && !self.firstBatchFed {
                self.firstBatchFed = true
                DYLog.shared.event("WORKS CAP OK total=\(self.totalCap)——资料+首批作品截获成立,继续滚动加载更多")
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

    /// 解析 JS 端精简后的 aweme/post 数据（{works:[{id,desc,cov,dur,imgs,u}],hasMore}）→ delegate
    private func handleWorks(_ body: String) {
        guard let d = body.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let slim = obj["works"] as? [[String: Any]] else {
            DYLog.shared.log("WORKSCAP works parse fail (slim)")
            return
        }
        let hasMore = (obj["hasMore"] as? Int ?? 0) != 0
        var works: [DYCapturedWork] = []
        for w in slim {
            guard let id = w["id"] as? String, !id.isEmpty else { continue }
            let urls = ((w["u"] as? String) ?? "").split(separator: "|").map(String.init)
                .filter { $0.hasPrefix("http") }
            guard !urls.isEmpty else { continue }
            let st = ((w["st"] as? String) ?? "").split(separator: ",").map { (Int($0) ?? 0) }
            works.append(DYCapturedWork(
                id: id,
                desc: w["desc"] as? String ?? "",
                coverUrl: w["cov"] as? String ?? "",
                playUrls: urls,
                durationMs: (w["dur"] as? NSNumber)?.intValue ?? 0,
                isImages: (w["imgs"] as? NSNumber)?.intValue == 1,
                createTime: (w["ct"] as? NSNumber)?.intValue ?? 0,
                mixName: w["mx"] as? String ?? "",
                mixId: w["mxid"] as? String ?? "",
                digg: st.indices.contains(0) ? st[0] : 0,
                comment: st.indices.contains(1) ? st[1] : 0,
                collect: st.indices.contains(2) ? st[2] : 0,
                share: st.indices.contains(3) ? st[3] : 0
            ))
        }
        DYLog.shared.event("WORKSCAP works ok n=\(works.count) hasMore=\(hasMore ? 1 : 0)")
        guard !works.isEmpty else { return }
        gotWorks = true
        // v170 累积合并（按 id 去重保序）+ 持续喂 delegate（自动加载剩余作品）
        let known = Set(capturedWorks.map { $0.id })
        let fresh = works.filter { !known.contains($0.id) }
        capturedHasMore = hasMore
        if !fresh.isEmpty {
            capturedWorks.append(contentsOf: fresh)
            lastGrowthAt = Date()
            let total = capturedWorks.count
            DYLog.shared.event("WORKSCAP works accumulated +\(fresh.count) → \(total) hasMore=\(hasMore ? 1 : 0)")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.worksCaptureDidCapture(works: self.capturedWorks, hasMore: self.capturedHasMore)
            }
        }
    }

    /// v172 合集内容：页面上下文 fetch mix/aweme（§5.3⑤A"WebView 内直接打 API"路线首次实装——
    /// 页面自己的 fetch 包装带签名/cookie；hook 已匹配 mix/ URL 会拦到响应）。
    /// 流程：新建 WebView 会话 load 抖音首页（挑战自动跑）→ complete+hooked → fetch → hook 拦截 → drain 解析。
    func fetchMix(mixId: String) {
        guard !mixId.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.webView != nil { self.teardown() }
            guard let wv = DYCreateWebViewWithInject(CGRect(x: 0, y: 0, width: 1, height: 1), DYProfileClient.webUA, Self.hookJS) as? UIView else {
                DYLog.shared.event("MIXCAP FAIL: 注入式 WKWebView 创建失败")
                return
            }
            self.webView = wv
            self.mode = .mix
            self.pendingMixId = mixId
            self.mixRequested = false
            self.gotWorks = false
            self.gotProfile = false
            self.totalCap = 0
            self.rehooked = false
            self.currentSecUid = ""
            self.capturedWorks = []
            self.capturedHasMore = false
            self.firstBatchFed = false
            self.lastGrowthAt = Date()
            DYLog.shared.log("MIXCAP load douyin home (doc-start inject) mixId=\(mixId)")
            wv.perform(NSSelectorFromString("loadRequest:"), with: NSURLRequest(url: URL(string: "https://www.douyin.com/?recommend=1")!))
            self.startPolling()
            self.deadlineTimer = Timer.scheduledTimer(withTimeInterval: 40, repeats: false) { [weak self] _ in
                DYLog.shared.log("MIXCAP deadline")
                self?.teardown()
            }
        }
    }

    /// mix/aweme 页面上下文 fetch（_dytag=mixcap 标记便于日志识别；页面 fetch 包装自动补签名）
    private static func mixFetchJS(mixId: String) -> String {
        """
        (function(){
          try{
            var u='/aweme/v1/web/mix/aweme/?mix_id=\(mixId)&cursor=0&count=20&source=channel_page&device_platform=webapp&aid=6383&channel=channel_pc_web&cookie_enabled=true&browser_language=zh-CN&browser_platform=Win32&browser_name=Chrome&browser_version=126.0.0.0&_dytag=mixcap';
            fetch(u,{credentials:'include'}).then(function(r){return r.text()}).then(function(t){
              try{ window.__dyCap.push({u:u,b:t}); }catch(e){}
            }).catch(function(e){
              try{ window.__dyCap.push({u:u,b:'FETCHERR:'+String(e)}); }catch(e2){}
            });
          }catch(e){ try{ window.__dyCap.push({u:'mixfetch-synerr',b:String(e)}); }catch(e2){} }
        })();
        """
    }

    /// v172 解析 mix/aweme 响应（grab 已 slim 成 works 数组）→ delegate
    private func handleMix(_ body: String) {
        guard let d = body.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let slim = obj["works"] as? [[String: Any]] else {
            DYLog.shared.log("MIXCAP parse fail (slim) body=\(body.prefix(80))")
            if body.hasPrefix("FETCHERR") { DYLog.shared.event("MIXCAP fetch error: \(body.prefix(120))") }
            return
        }
        let mixName = obj["mixName"] as? String ?? ""
        var works: [DYCapturedWork] = []
        for w in slim {
            guard let id = w["id"] as? String, !id.isEmpty else { continue }
            let urls = ((w["u"] as? String) ?? "").split(separator: "|").map(String.init)
                .filter { $0.hasPrefix("http") }
            guard !urls.isEmpty else { continue }
            let st = ((w["st"] as? String) ?? "").split(separator: ",").map { (Int($0) ?? 0) }
            works.append(DYCapturedWork(
                id: id,
                desc: w["desc"] as? String ?? "",
                coverUrl: w["cov"] as? String ?? "",
                playUrls: urls,
                durationMs: (w["dur"] as? NSNumber)?.intValue ?? 0,
                isImages: (w["imgs"] as? NSNumber)?.intValue == 1,
                createTime: (w["ct"] as? NSNumber)?.intValue ?? 0,
                mixName: w["mx"] as? String ?? mixName,
                mixId: pendingMixId,
                digg: st.indices.contains(0) ? st[0] : 0,
                comment: st.indices.contains(1) ? st[1] : 0,
                collect: st.indices.contains(2) ? st[2] : 0,
                share: st.indices.contains(3) ? st[3] : 0
            ))
        }
        DYLog.shared.event("MIXCAP ok n=\(works.count) mixName=\(mixName)")
        guard !works.isEmpty else { return }
        let wid = pendingMixId
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.worksCaptureDidCapture(mixWorks: works, mixId: wid, mixName: mixName)
            self?.teardown()
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
