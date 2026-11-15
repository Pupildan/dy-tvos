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
    /// v175 合集内集数（myDV nx3 同款：mix_info.statis.current_episode，0=无则按序号兜底）
    let episode: Int
}

/// v174 数据泵全面重构（真机日志实锤的三大问题）：
/// ① 作品分页靠网页滚动从未成功（离屏 WebView scrollTo 不触发懒加载，每会话停在首批）；
/// ② 作者页慢=每次新建会话加载作者页等挑战；
/// ③ 会话冲突（mix 会话被 profile 打断等）。
///
/// 新架构：**一个持久会话（离屏 WebView 加载抖音首页过挑战）+ 全部数据走页面上下文 fetch**
/// （v172 真机已验证：页面 fetch 包装自带签名/cookie，`MIXCAP ok n=15` 1 秒完成）。
/// 请求带 _dytag 标记（profcap/postcap/mixcap），hook 拦响应，drain 按 tag 分发解析；
/// 作品分页由本类驱动（hasMore=1 自动排队下一页 max_cursor），不再依赖网页行为。
/// 会话复用：作者页/合集屏切换零加载；空闲 30s 或 180s deadline 才收摊。
final class DYWorksCapture: NSObject {
    static let shared = DYWorksCapture()

    /// UI 订阅截获结果（DYProfileScreen/DYMixScreen 注册；回调已在主线程）。
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
    private var rehooked = false
    private var pollCount = 0
    private var totalCap = 0

    /// v174 会话就绪（hooked + interactive/complete）后才开始发 fetch
    private var sessionReady = false
    private var readySeenAt = Date.distantPast
    private var lastActivityAt = Date()
    /// 待发请求队列（sessionReady 后每 drain tick 发一条，天然节流）
    private var pendingQueue: [String] = []
    /// 已发请求标记集合（drain 按 _dytag 分发响应；profcap 每作者一次，postcap 按页）
    private var currentAuthorSec = ""
    /// 作品累积（按 id 去重保序）
    private var capturedWorks: [DYCapturedWork] = []
    private var capturedHasMore = false
    private var lastMaxCursor = -1
    private var postPagesFetched = 0
    private let postMaxPages = 8
    /// v175 去重：RootView.onChange 与屏 onAppear 曾双发 profcap/postcap（真机日志实锤，白等 2s）
    private var lastAuthorQueueAt = Date.distantPast
    /// v175 aweme/detail 拿到的权威合集名（mix/aweme 响应里 mixName 常空）
    private var pendingMixName = ""

    // MARK: - 对外入口

    /// 拉取作者资料+作品（会话就绪即发 profcap+postcap；hasMore 自动翻页）
    func fetch(secUid: String) {
        guard !secUid.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let sameAuthor = (self.currentAuthorSec == secUid)
            if !sameAuthor {
                self.currentAuthorSec = secUid
                self.capturedWorks = []
                self.capturedHasMore = false
                self.lastMaxCursor = -1
                self.postPagesFetched = 0
            }
            self.lastActivityAt = Date()
            // 主页屏实例可能是新的（state 空）：已累积作品立即补发，不用等网络
            if !self.capturedWorks.isEmpty {
                let works = self.capturedWorks
                let more = self.capturedHasMore
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.worksCaptureDidCapture(works: works, hasMore: more)
                }
            }
            self.ensureSession()
            // 资料每次刷新（屏实例新，user 空），但 3s 内同作者只排一次队（双 fire 去重）
            let now = Date()
            guard now.timeIntervalSince(self.lastAuthorQueueAt) > 3 else { return }
            self.lastAuthorQueueAt = now
            self.pendingQueue.append(Self.profileFetchURL(secUid: secUid))
            if sameAuthor {
                if self.capturedHasMore, self.postPagesFetched < self.postMaxPages {
                    self.pendingQueue.append(Self.postFetchURL(secUid: secUid, maxCursor: max(0, self.lastMaxCursor)))
                }
            } else {
                self.pendingQueue.append(Self.postFetchURL(secUid: secUid, maxCursor: 0))
            }
        }
    }

    /// 合集内容：页面上下文 fetch mix/aweme（§5.3⑤A 路线，v172 真机验证成立）。
    /// v175 权威化（myDV 反编译实锤）：手机端 proto 解析器 s13 **从不填 MixInfo**（恒 null），
    /// f14/f6 无权威依据且真机合集错位 → mixId 为空时先打 aweme/detail（myDV u11:3992 同款端点）
    /// 拿 aweme_detail.mix_info.mix_id，再发 mix/aweme。
    func fetchMix(mixId: String, awemeId: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastActivityAt = Date()
            self.ensureSession()
            if !mixId.isEmpty {
                self.pendingQueue.append(Self.mixFetchURL(mixId: mixId))
            } else if !awemeId.isEmpty {
                self.pendingQueue.append(Self.detailFetchURL(awemeId: awemeId))
            }
        }
    }

    // MARK: - 请求 URL（页面上下文 fetch，页面包装自动补 webCommon/msToken/a_bogus）

    private static func profileFetchURL(secUid: String) -> String {
        "/aweme/v1/web/user/profile/other/?device_platform=webapp&aid=6383&channel=channel_pc_web&sec_user_id=\(secUid)&publish_video_strategy_type=2&source=channel_page&_dytag=profcap"
    }

    /// v175 逐参数照抄 myDV UserWorksResponse 方法（u11.java 3678-3703，反编译实锤）：
    /// sec_user_id/count/max_cursor/locate_item_id/locate_query/show_live_replay_strategy/
    /// need_time_list(首页1 翻页0)/time_list_query/whale_cut_token/cut_version/
    /// publish_video_strategy_type/from_user_page/version_code=290100/version_name=29.1.0
    /// v174 缺 6 参数且 need_time_list 恒 1 → 第二页 200 空（真机 len=17 实锤）。
    private static func postFetchURL(secUid: String, maxCursor: Int) -> String {
        let needTimeList = maxCursor == 0 ? "1" : "0"
        return "/aweme/v1/web/aweme/post/?device_platform=webapp&aid=6383&channel=channel_pc_web&sec_user_id=\(secUid)&count=20&max_cursor=\(maxCursor)&locate_item_id=&locate_query=false&show_live_replay_strategy=1&need_time_list=\(needTimeList)&time_list_query=0&whale_cut_token=&cut_version=1&publish_video_strategy_type=2&from_user_page=1&version_code=290100&version_name=29.1.0&_dytag=postcap"
    }

    private static func mixFetchURL(mixId: String) -> String {
        "/aweme/v1/web/mix/aweme/?mix_id=\(mixId)&cursor=0&count=20&source=channel_page&_dytag=mixcap"
    }

    /// v175 myDV u11:3992 同款 aweme/detail（§7.2 探针全通）——权威取 mix_info.mix_id
    private static func detailFetchURL(awemeId: String) -> String {
        "/aweme/v1/web/aweme/detail/?aweme_id=\(awemeId)&request_source=600&origin_type=quick_player&device_platform=webapp&aid=6383&channel=channel_pc_web&_dytag=detailcap"
    }

    /// 页面上下文 fetch（hook 已在 doc-start 注入，响应自动进 __dyCap）
    private static func fetchJS(url: String) -> String {
        """
        (function(){
          try{
            fetch('\(url)',{credentials:'include'}).then(function(r){return r.text()}).then(function(t){
              try{ window.__dyCap.push({u:'\(url)',b:t}); }catch(e){}
            }).catch(function(e){
              try{ window.__dyCap.push({u:'\(url)',b:'FETCHERR:'+String(e)}); }catch(e2){}
            });
          }catch(e){ try{ window.__dyCap.push({u:'\(url.prefix(60))...',b:'SYNERR:'+String(e)}); }catch(e2){} }
        })();
        """
    }

    // MARK: - 会话管理

    private func ensureSession() {
        guard webView == nil else { return }
        guard let wv = DYCreateWebViewWithInject(CGRect(x: 0, y: 0, width: 1, height: 1), DYProfileClient.webUA, Self.hookJS) as? UIView else {
            DYLog.shared.event("SESSION FAIL: 注入式 WKWebView 创建失败")
            return
        }
        webView = wv
        sessionReady = false
        readySeenAt = .distantPast
        rehooked = false
        pollCount = 0
        totalCap = 0
        lastActivityAt = Date()
        DYLog.shared.log("SESSION boot douyin home (doc-start inject) — 持久会话")
        wv.perform(NSSelectorFromString("loadRequest:"), with: NSURLRequest(url: URL(string: "https://www.douyin.com/?recommend=1")!))
        startPolling()
        deadlineTimer?.invalidate()
        deadlineTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
            DYLog.shared.log("SESSION deadline (180s)")
            self?.teardown()
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pollCount += 1
            self.drain(tag: "p\(self.pollCount)")
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func teardown() {
        pollTimer?.invalidate(); pollTimer = nil
        deadlineTimer?.invalidate(); deadlineTimer = nil
        webView = nil
        sessionReady = false
        pendingQueue = []
    }

    // MARK: - 轮询 drain：会话就绪判定 + 发队列请求 + 分发响应

    private func drain(tag: String) {
        guard webView != nil else { return }
        // 空闲收摊（30s 无任何请求/响应活动）
        if Date().timeIntervalSince(lastActivityAt) > 30 {
            DYLog.shared.event("SESSION idle teardown (30s) total=\(self.totalCap)")
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
                DYLog.shared.log("SESSION[\(tag)] hooked=0 → evaluateJavaScript 补装 hook")
                self.evalJS(Self.hookJS, tag: "rehook")
            }
            // 会话就绪判定（v173 验证：interactive+1.5s 即视为就绪，不等 complete）
            if !self.sessionReady, hooked {
                let rs = diag["rs"] as? String ?? ""
                let ready = (rs == "complete")
                    || (rs == "interactive" && self.readySeenAt != .distantPast
                        && Date().timeIntervalSince(self.readySeenAt) > 1.5)
                if rs == "interactive", self.readySeenAt == .distantPast {
                    self.readySeenAt = Date()
                }
                if ready {
                    self.sessionReady = true
                    DYLog.shared.event("SESSION ready rs=\(rs) → 队列 \(self.pendingQueue.count) 条待发")
                }
            }
            // 发队列（v175 提速：每 tick 连发 2 条，profile+post 不再串行等 2s）
            if self.sessionReady, !self.pendingQueue.isEmpty {
                for _ in 0..<min(2, self.pendingQueue.count) {
                    let url = self.pendingQueue.removeFirst()
                    self.lastActivityAt = Date()
                    self.totalCap += 1
                    let tagWord = url.contains("_dytag=profcap") ? "profcap"
                        : url.contains("_dytag=postcap") ? "postcap"
                        : url.contains("_dytag=detailcap") ? "detailcap" : "mixcap"
                    DYLog.shared.log("SESSION fire \(tagWord) → \(url.prefix(100))")
                    self.evalJS(Self.fetchJS(url: url), tag: tagWord)
                }
            }
            // 分发响应
            for item in cap {
                let u = item["u"] as? String ?? "?"
                let b = item["b"] as? String ?? ""
                guard u.contains("_dytag=") else {
                    // 页面自身请求（不再加载作者页后几乎不会有；照旧打日志备查）
                    if u.contains("aweme/post") || u.contains("user/profile") || u.contains("mix/") {
                        DYLog.shared.log("SESSION page-req len=\(b.count) u=\(u.prefix(80))")
                    }
                    continue
                }
                self.lastActivityAt = Date()
                if u.contains("_dytag=profcap") {
                    DYLog.shared.event("CAP profcap len=\(b.count)")
                    self.handleProfile(b)
                } else if u.contains("_dytag=postcap") {
                    DYLog.shared.event("CAP postcap len=\(b.count)")
                    self.handleWorks(b)
                } else if u.contains("_dytag=detailcap") {
                    DYLog.shared.event("CAP detailcap len=\(b.count)")
                    self.handleDetail(b)
                } else if u.contains("_dytag=mixcap") {
                    DYLog.shared.event("CAP mixcap len=\(b.count)")
                    self.handleMix(b)
                }
            }
        }
    }

    // MARK: - 解析

    /// 解析 profile/other 响应 → DYProfileUser → delegate
    private func handleProfile(_ body: String) {
        guard let d = body.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              (obj["status_code"] as? Int ?? -1) == 0,
              let user = obj["user"] as? [String: Any] else {
            DYLog.shared.log("CAP profile parse fail body=\(body.prefix(60))")
            return
        }
        var avatar = ""
        if let at = user["avatar_thumb"] as? [String: Any], let ul = at["url_list"] as? [String] {
            avatar = ul.first(where: { $0.hasPrefix("http") }) ?? ""
        }
        let u = DYProfileUser(
            nickname: user["nickname"] as? String ?? "",
            avatarUrl: avatar,
            secUid: user["sec_uid"] as? String ?? currentAuthorSec,
            signature: user["signature"] as? String ?? "",
            followerCount: (user["follower_count"] as? NSNumber)?.intValue ?? 0,
            followingCount: (user["following_count"] as? NSNumber)?.intValue ?? 0,
            awemeCount: (user["aweme_count"] as? NSNumber)?.intValue ?? 0,
            totalFavorited: (user["total_favorited"] as? NSNumber)?.intValue ?? 0
        )
        DYLog.shared.event("CAP profile ok nick=\(u.nickname) fans=\(u.followerCount) works=\(u.awemeCount)")
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.worksCaptureDidCapture(profile: u)
        }
    }

    /// 解析 aweme/post 响应（grab slim 或裸 JSON 兜底）→ 累积 → delegate → hasMore 自动翻页
    private func handleWorks(_ body: String) {
        if body.hasPrefix("FETCHERR") || body.hasPrefix("SYNERR") {
            DYLog.shared.event("CAP post fetch error: \(body.prefix(120))")
            return
        }
        var works: [DYCapturedWork] = []
        var hasMore = false
        var nextCursor = lastMaxCursor
        var mixName = ""
        if let d = body.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
            if let slim = obj["works"] as? [[String: Any]] {
                // grab 已精简的形态
                works = Self.parseSlim(slim)
                hasMore = (obj["hasMore"] as? Int ?? 0) != 0
                // v175 myDV 权威：翻页游标 = 响应 cursor（UserWorksResponse.getCursor()），非 max_cursor
                if let c = obj["cursor"] as? Int, c > 0 { nextCursor = c }
                else if let mc = obj["maxCursor"] as? Int { nextCursor = mc }
                mixName = obj["mixName"] as? String ?? ""
            } else if let list = obj["aweme_list"] as? [[String: Any]] {
                // 裸 JSON 兜底（grab 端 JSON.parse 失败/超长响应）
                works = Self.parseFull(list)
                hasMore = (obj["has_more"] as? Int ?? 0) != 0
                if let c = obj["cursor"] as? Int, c > 0 { nextCursor = c }
                else if let mc = obj["max_cursor"] as? Int { nextCursor = mc }
                if let mi = obj["mix_info"] as? [String: Any] { mixName = mi["mix_name"] as? String ?? "" }
            }
        }
        DYLog.shared.event("CAP post ok n=\(works.count) hasMore=\(hasMore ? 1 : 0) cursor=\(nextCursor)")
        guard !works.isEmpty else { return }
        let known = Set(capturedWorks.map { $0.id })
        let fresh = works.filter { !known.contains($0.id) }
        capturedHasMore = hasMore
        if !fresh.isEmpty {
            capturedWorks.append(contentsOf: fresh)
            let total = capturedWorks.count
            DYLog.shared.event("CAP works accumulated +\(fresh.count) → \(total) hasMore=\(hasMore ? 1 : 0)")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.worksCaptureDidCapture(works: self.capturedWorks, hasMore: self.capturedHasMore)
            }
        }
        // v175 分页引擎：myDV 完整参数 + 响应 cursor 翻页（v174 用 max_cursor + 缺 6 参数 → 第二页空）
        if hasMore, nextCursor != lastMaxCursor, postPagesFetched < postMaxPages, !currentAuthorSec.isEmpty {
            postPagesFetched += 1
            lastMaxCursor = nextCursor
            let url = Self.postFetchURL(secUid: currentAuthorSec, maxCursor: nextCursor)
            DYLog.shared.log("CAP post page \(postPagesFetched) queued cursor=\(nextCursor)")
            pendingQueue.append(url)
        }
        _ = mixName
    }

    /// v175 权威合集 id：aweme/detail 响应 → aweme_detail.mix_info → mix/aweme
    /// （myDV 手机端 s13 恒不填 MixInfo；f14/f6 无权威依据且真机合集错位，弃用）
    private func handleDetail(_ body: String) {
        guard let d = body.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
            DYLog.shared.log("CAP detail parse fail body=\(body.prefix(60))")
            return
        }
        let detail = obj["aweme_detail"] as? [String: Any] ?? obj
        guard let mi = detail["mix_info"] as? [String: Any] else {
            DYLog.shared.event("CAP detail no mix_info keys=\(detail.keys.count)")
            return
        }
        var mid = ""
        if let s = mi["mix_id"] as? String { mid = s }
        else if let n = mi["mix_id"] as? NSNumber { mid = n.stringValue }
        let name = mi["mix_name"] as? String ?? ""
        DYLog.shared.event("CAP detail mixId=\(mid) name=\(name)")
        guard !mid.isEmpty else { return }
        pendingMixName = name
        pendingQueue.insert(Self.mixFetchURL(mixId: mid), at: 0)
    }

    /// 解析 mix/aweme 响应 → delegate（grab slim 或裸 JSON 兜底）
    private func handleMix(_ body: String) {
        if body.hasPrefix("FETCHERR") || body.hasPrefix("SYNERR") {
            DYLog.shared.event("CAP mix fetch error: \(body.prefix(120))")
            return
        }
        var works: [DYCapturedWork] = []
        var mixName = ""
        if let d = body.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
            if let slim = obj["works"] as? [[String: Any]] {
                works = Self.parseSlim(slim)
                mixName = obj["mixName"] as? String ?? ""
            } else if let list = obj["aweme_list"] as? [[String: Any]] {
                works = Self.parseFull(list)
                if let mi = obj["mix_info"] as? [String: Any] { mixName = mi["mix_name"] as? String ?? "" }
            }
        }
        DYLog.shared.event("CAP mix ok n=\(works.count) mixName=\(mixName.isEmpty ? pendingMixName : mixName)")
        guard !works.isEmpty else {
            DYLog.shared.log("CAP mix empty body=\(body.prefix(60))")
            return
        }
        let mixIdOfFirst = works.first?.mixId ?? ""
        let finalName = mixName.isEmpty ? pendingMixName : mixName
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.worksCaptureDidCapture(mixWorks: works, mixId: mixIdOfFirst, mixName: finalName)
        }
    }

    /// grab 精简形态解析（{id,desc,cov,dur,ct,mx,mxid,st,imgs,u}）
    private static func parseSlim(_ slim: [[String: Any]]) -> [DYCapturedWork] {
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
                share: st.indices.contains(3) ? st[3] : 0,
                episode: (w["ep"] as? NSNumber)?.intValue ?? 0
            ))
        }
        return works
    }

    /// 裸 web JSON 兜底解析（与 JS slim 同字段路径；grab 端 parse 失败时用）
    private static func parseFull(_ list: [[String: Any]]) -> [DYCapturedWork] {
        var works: [DYCapturedWork] = []
        for a in list {
            guard let id = a["aweme_id"] as? String, !id.isEmpty else { continue }
            let v = a["video"] as? [String: Any] ?? [:]
            var cand: [String] = []
            for key in ["play_addr", "play_addr_265", "download_addr"] {
                if let pa = v[key] as? [String: Any], let ul = pa["url_list"] as? [String] {
                    cand.append(contentsOf: ul)
                }
            }
            let urls = cand.filter { $0.hasPrefix("http") }
            guard !urls.isEmpty else { continue }
            var cov = ""
            if let c = v["cover"] as? [String: Any], let ul = c["url_list"] as? [String], let f = ul.first {
                cov = f
            } else if let oc = v["origin_cover"] as? [String: Any], let ul = oc["url_list"] as? [String], let f = ul.first {
                cov = f
            }
            let st = a["statistics"] as? [String: Any] ?? [:]
            func n(_ key: String) -> Int { (st[key] as? NSNumber)?.intValue ?? 0 }
            var mixName = ""; var mixId = ""
            var episode = 0
            if let mi = a["mix_info"] as? [String: Any] {
                mixName = mi["mix_name"] as? String ?? ""
                if let mid = mi["mix_id"] as? String { mixId = mid }
                else if let midn = mi["mix_id"] as? NSNumber { mixId = midn.stringValue }
                // myDV nx3: mixInfo.statis.currentEpisode
                if let statis = mi["statis"] as? [String: Any], let ep = statis["current_episode"] as? NSNumber {
                    episode = ep.intValue
                }
            }
            works.append(DYCapturedWork(
                id: id,
                desc: a["desc"] as? String ?? "",
                coverUrl: cov,
                playUrls: urls,
                durationMs: (v["duration"] as? NSNumber)?.intValue ?? 0,
                isImages: (a["images"] as? [[String: Any]])?.isEmpty == false,
                createTime: (a["create_time"] as? NSNumber)?.intValue ?? 0,
                mixName: mixName,
                mixId: mixId,
                digg: n("digg_count"),
                comment: n("comment_count"),
                collect: n("collect_count"),
                share: n("share_count"),
                episode: episode
            ))
        }
        return works
    }

    // MARK: - JS

    private func evalJS(_ js: String, tag: String, done: ((Any?) -> Void)? = nil) {
        guard let wv = webView else { return }
        let handler: @convention(block) (NSObject?, NSObject?) -> Void = { result, error in
            if let error = error as? NSError {
                DYLog.shared.log("SESSION[\(tag)] js err: \(error.localizedDescription)")
            }
            done?(result)
        }
        let block = unsafeBitCast(handler, to: AnyObject.self)
        wv.perform(NSSelectorFromString("evaluateJavaScript:completionHandler:"), with: js, with: block)
    }

    /// 抽回 __dyCap + 诊断透视
    private static let drainJS = """
    (function(){
      var cap=[]; try{ cap=window.__dyCap.splice(0); }catch(e){}
      var diag={rs:'',href:'',hooked:false,n:cap.length};
      try{ diag.rs=document.readyState; }catch(e){}
      try{ diag.href=String(location.href).slice(0,90); }catch(e){}
      try{ diag.hooked=!!window.__dyHooked; }catch(e){}
      diag.cap=cap; return JSON.stringify(diag);
    })();
    """

    /// document-start 注入的拦截器：命中资料/作品/合集端点（含 _dytag 标记请求）的响应体存 window.__dyCap。
    /// aweme/post 与 mix/aweme 响应在 JS 端预解析精简（每条只取 id/desc/cover/直链/duration/统计，体积 300KB+→~10KB）。
    private static let hookJS = """
    (function(){
      if(window.__dyHooked) return; window.__dyHooked=true; window.__dyCap=[];
      function grab(u,b){ try{
        if(!u||!b) return;
        var s=String(u);
        if(s.indexOf('aweme/post')<0&&s.indexOf('series/')<0&&s.indexOf('mix/')<0&&s.indexOf('user/profile')<0&&s.indexOf('aweme/detail')<0) return;
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
              var ep=0; if(a.mix_info&&a.mix_info.statis&&a.mix_info.statis.current_episode)ep=a.mix_info.statis.current_episode;
              var st=[0,0,0,0];
              if(a.statistics){st=[a.statistics.digg_count||0,a.statistics.comment_count||0,a.statistics.collect_count||0,a.statistics.share_count||0];}
              slim.push({id:a.aweme_id||'',desc:a.desc||'',cov:cov,dur:v.duration||0,ct:a.create_time||0,mx:mx,mxid:mxid,ep:ep,
                st:st.join(','),imgs:(a.images&&a.images.length)?1:0,u:cand.join('|')});
            }
            var mn=''; if(j.mix_info&&j.mix_info.mix_name)mn=j.mix_info.mix_name;
            window.__dyCap.push({u:s.slice(0,120),b:JSON.stringify({works:slim,hasMore:(j.has_more||0),maxCursor:(j.max_cursor||0),cursor:(j.cursor||0),mixName:mn})});
            return;
          }
        }
        window.__dyCap.push({u:s.slice(0,120),b:body.slice(0,300000)});
      }catch(e){} }
      var xo=XMLHttpRequest.prototype.open, xs=XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open=function(m,u){ this.__u=u; return xo.apply(this,arguments); };
      XMLHttpRequest.prototype.send=function(){ var x=this; this.__u=String(this.__u||'');
        this.addEventListener('readystatechange',function(){ if(x.readyState===4){ try{ var t=x.responseType; if(!t||t==='text'||t==='json'){ grab(x.__u,(t==='json')?x.response:x.responseText); } }catch(e){} } });
        return xs.apply(this,arguments); };
      var of=window.fetch;
      if(of){ window.fetch=function(){ var a=arguments,u=(a[0]&&a[0].url)||a[0]; u=String(u);
        return of.apply(this,arguments).then(function(r){ try{ var c=r.clone(); c.text().then(function(t){ grab(u,t); }).catch(function(){}); }catch(e){} return r; }); }; }
    })();
    """
}
