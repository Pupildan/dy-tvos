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
/// 请求标记只存 JS 本地映射（v178 起 URL 完全干净，见 tagFor），hook 拦响应，drain 按 tag 分发解析；
/// 翻页以**页面自己的懒加载**为主通道（真实 viewport 滚动泵），自拼请求只作并行兜底
/// 且参数集 1:1 照抄页面包装后真实发出的原生 URL（nativePostURL 模板）。
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
    private let postMaxPages = 20
    /// v175 去重：RootView.onChange 与屏 onAppear 曾双发 profcap/postcap（真机日志实锤，白等 2s）
    private var lastAuthorQueueAt = Date.distantPast
    /// v175 aweme/detail 拿到的权威合集名（mix/aweme 响应里 mixName 常空）
    private var pendingMixName = ""
    /// v176 反编译实锤：myDV u11.F0 按端点设 referer（post → https://www.douyin.com/user/）。
    /// 页面上下文 fetch 不能自定义 Referer 头（forbidden header）→ 用 history.replaceState 切 document URL，
    /// 零加载让浏览器自动带上正确 Referer。首屏翻页被软拒（len=17 空列表）就是 referer 不匹配。
    private var desiredPagePath = ""
    /// v176 翻页节流：连发两页间隔 <1s 触发风控（真机实锤），改为 ≥3s
    private var lastPostFireAt = Date.distantPast
    private var postEarliestFireAt = Date.distantPast
    /// v176 空响应退避重试（最多 2 次）
    private var postEmptyRetries = 0
    /// v176 缓存资料（同作者重开只补发缓存，不再重复请求触发风控）
    private var cachedProfile: DYProfileUser?
    /// v178 页面包装后真实发出的原生 aweme/post URL（hook 保留完整串）→ 翻页参数模板
    private var nativePostURL = ""
    private var nativeURLLogged = false
    /// v179 响应的 max_cursor（与 cursor 分开保存，软拒时换游标值重试）
    private var altCursor = 0
    /// v179 翻页参数变体推进（0→换游标值→换游标键，共 3 种，全拒则停发自拼请求）
    private var pagingVariant = 0
    /// v180 真导航竞态护栏：导航时刻 + 新 document hook 稳定计数
    private var navigationPendingAt = Date.distantPast
    private var hookedStableCount = 0
    private var loadedAuthorSec = ""
    /// v180 变体推进节流（XHR/fetch 双通道会同时回两条空响应，避免一次连跳两级）
    private var lastVariantAt = Date.distantPast
    /// v181 全端点透视去重（同一 URL 只打一次日志）
    private var seenURLLogged: Set<String> = []

    // MARK: - 对外入口

    /// v180 网格触底：不再自拼翻页 URL（翻页墙实锤），只推页面作者页滚动，
    /// 让页面自己发懒加载请求；响应经 page-req 通道按 id 去重累积。
    func requestMoreWorks() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.capturedHasMore, !self.currentAuthorSec.isEmpty else { return }
            self.lastActivityAt = Date()
            self.evalJS(Self.scrollJS, tag: "scroll-more")
            DYLog.shared.event("CAP post scroll-more → page-native lazy paging (no self-issued URL)")
        }
    }

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
                self.postEmptyRetries = 0
                self.cachedProfile = nil
                self.lastPostFireAt = .distantPast
                self.postEarliestFireAt = .distantPast
                self.pendingQueue = []
                self.lastAuthorQueueAt = .distantPast   // 换作者立即放行，不能被 3s 去重误挡
                // v179 换作者必须清掉旧作者的原生 URL 模板/变体状态（否则翻页会用旧作者签名参数）
                self.nativePostURL = ""
                self.nativeURLLogged = false
                self.altCursor = 0
                self.pagingVariant = 0
            }
            self.lastActivityAt = Date()
            // 主页屏实例可能是新的（state 空）：已累积作品/资料立即补发，不用等网络
            if !self.capturedWorks.isEmpty || self.cachedProfile != nil {
                let works = self.capturedWorks
                let more = self.capturedHasMore
                let prof = self.cachedProfile
                DispatchQueue.main.async { [weak self] in
                    if let prof { self?.delegate?.worksCaptureDidCapture(profile: prof) }
                    if !works.isEmpty { self?.delegate?.worksCaptureDidCapture(works: works, hasMore: more) }
                }
                // v176 同作者重开：有缓存就不再重复打第一页（19:21:24 真机实锤重复请求后连第一页都变空）
                if sameAuthor, !self.capturedWorks.isEmpty {
                    // v180 同作者重开：只补缓存 + 推页面滚动，不再自拼翻页 URL（翻页墙）
                    if self.capturedHasMore, self.pendingQueue.isEmpty {
                        self.evalJS(Self.scrollJS, tag: "reopen-scroll")
                    }
                    return
                }
            }
            self.ensureSession(secUid: secUid)
            // 资料每次刷新（屏实例新，user 空），但 3s 内同作者只排一次队（双 fire 去重）
            let now = Date()
            guard now.timeIntervalSince(self.lastAuthorQueueAt) > 3 else { return }
            self.lastAuthorQueueAt = now
            self.postEmptyRetries = 0
            self.postPagesFetched = 0
            // v176 document URL 对齐端点 referer（队列首项特殊指令，sessionReady 后执行）
            self.desiredPagePath = "/user/\(secUid)"
            self.pendingQueue.append("_push:/user/\(secUid)")
            self.pendingQueue.append(Self.profileFetchURL(secUid: secUid))
            self.pendingQueue.append(Self.postFetchURL(secUid: secUid, maxCursor: 0))
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
                // u11.o: mix/aweme → https://www.douyin.com/collection/
                self.pendingQueue.append("_push:/collection/\(mixId)")
                self.pendingQueue.append(Self.mixFetchURL(mixId: mixId))
            } else if !awemeId.isEmpty {
                // u11.o: aweme/detail → https://www.douyin.com/video/
                self.pendingQueue.append("_push:/video/\(awemeId)")
                self.pendingQueue.append(Self.detailFetchURL(awemeId: awemeId))
            }
        }
    }

    // MARK: - 请求 URL（页面上下文 fetch，页面包装自动补 webCommon/msToken/a_bogus）

    /// ⚠️ v178（v175/v176/v177 连续 3 版自拼翻页 URL 全部 `{"status_code":0}` 软拒，按铁律判死该路线）：
    /// ① 标记**完全不进实际 URL**——query 不行（v176 实锤服务端不认识的参数破坏 a_bogus）、
    ///    fragment 也不行（v177 实锤页面签名包装把 URL 字符串含 fragment 一起算签名，服务端却收不到 fragment）。
    ///    改用 JS 本地 `window.__dyTagMap[u]=tag` 映射，fetchJS 回推时本地拼 `#tag` 仅供 Swift 分发。
    /// ② 翻页参数集不再照抄 myDV，改为 1:1 照抄**页面包装后真实发出的原生 URL**（见 nativePostURL）。
    private static func tagFor(_ url: String) -> String {
        if url.contains("user/profile") { return "profcap" }
        if url.contains("aweme/post") { return "postcap" }
        if url.contains("aweme/detail") { return "detailcap" }
        return "mixcap"
    }

    private static func profileFetchURL(secUid: String) -> String {
        "/aweme/v1/web/user/profile/other/?device_platform=webapp&aid=6383&channel=channel_pc_web&sec_user_id=\(secUid)&publish_video_strategy_type=2&source=channel_page"
    }

    /// v175 逐参数照抄 myDV UserWorksResponse 方法（u11.java 3678-3703，反编译实锤）：
    /// sec_user_id/count/max_cursor/locate_item_id/locate_query/show_live_replay_strategy/
    /// need_time_list(首页1 翻页0)/time_list_query/whale_cut_token/cut_version/
    /// publish_video_strategy_type/from_user_page/version_code=290100/version_name=29.1.0
    /// v174 缺 6 参数且 need_time_list 恒 1 → 第二页 200 空（真机 len=17 实锤）。
    private static func postFetchURL(secUid: String, maxCursor: Int, count: Int = 100) -> String {
        let needTimeList = maxCursor == 0 ? "1" : "0"
        return "/aweme/v1/web/aweme/post/?device_platform=webapp&aid=6383&channel=channel_pc_web&sec_user_id=\(secUid)&count=\(count)&max_cursor=\(maxCursor)&locate_item_id=&locate_query=false&show_live_replay_strategy=1&need_time_list=\(needTimeList)&time_list_query=0&whale_cut_token=&cut_version=1&publish_video_strategy_type=2&from_user_page=1&version_code=290100&version_name=29.1.0"
    }

    /// v179 权威翻页 URL：以页面 jsvmp 包装后**真实发出的原生 aweme/post URL** 为模板
    /// （v178 真机 `NATIVE POST URL[n]` 打全：verifyFp/fp/msToken/a_bogus/uifid 都是页面加的）。
    /// **字符串级替换**，不做 percent 解码/重编码——URLComponents 会改写空值与 %2F，破坏与页面
    /// 原生请求的字节一致性。删除所有会话绑定参数，交给页面包装器按新 URL 重签全套。
    /// myDV u11:3680 权威：`need_time_list = (j==0 ? "1" : "0")`，翻页 j!=0 必须是 0（v178 模板复制时漏改）。
    /// variant：0=标准(max_cursor=cursor)；1=换游标值(max_cursor=响应 max_cursor)；
    ///          2=换游标键(cursor=<游标> + max_cursor=0)。
    private static func nativePagedPostURL(template: String, secUid: String,
                                           cursor: Int, altCursor: Int, variant: Int) -> String? {
        guard let qm = template.firstIndex(of: "?") else { return nil }
        let head = String(template[...qm])          // 含 '?'
        let query = String(template[template.index(after: qm)...])
        let dropKeys: Set<String> = ["a_bogus", "msToken", "verifyFp", "verify_fp", "fp",
                                     "uifid", "webid", "_signature", "X-Bogus", "_dytag"]
        var out: [String] = []
        var hasCursorKey = false
        var hasCursorParam = false
        for part in query.split(separator: "&", omittingEmptySubsequences: false) {
            let kv = String(part).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(kv[0])
            if dropKeys.contains(key) { continue }
            var val = kv.count > 1 ? String(kv[1]) : ""
            switch key {
            case "max_cursor":
                hasCursorKey = true
                val = (variant == 2) ? "0" : String(variant == 1 && altCursor > 0 ? altCursor : cursor)
            case "cursor":
                hasCursorParam = true
                val = String(variant == 1 && altCursor > 0 ? altCursor : cursor)
            case "need_time_list":
                val = "0"                       // myDV：翻页恒 0
            case "sec_user_id", "secUid":
                val = secUid
            default: break
            }
            out.append(key + "=" + val)
        }
        if variant == 2, !hasCursorParam {
            out.append("cursor=" + String(cursor))
        }
        guard hasCursorKey || hasCursorParam else { return nil }
        // v179：模板是页面包装后的绝对 URL，而首屏请求是相对路径——签名包装对两种形态
        // 算出的 a_bogus 可能不同。统一还原成相对路径，与已通过验签的首屏请求逐字节同构。
        var result = head + out.joined(separator: "&")
        if let r = result.range(of: "https://www.douyin.com/") {
            result = "/" + String(result[r.upperBound...])
        }
        return result
    }

    private static func mixFetchURL(mixId: String) -> String {
        "/aweme/v1/web/mix/aweme/?mix_id=\(mixId)&cursor=0&count=20&source=channel_page"
    }

    /// v175 myDV u11:3992 同款 aweme/detail（§7.2 探针全通）——权威取 mix_info.mix_id
    private static func detailFetchURL(awemeId: String) -> String {
        "/aweme/v1/web/aweme/detail/?aweme_id=\(awemeId)&request_source=600&origin_type=quick_player&device_platform=webapp&aid=6383&channel=channel_pc_web"
    }

    /// 页面上下文请求：URL 完全干净（无任何自定义标记），标记只存 JS 本地映射。
    /// v178 关键：抖音 jsvmp 签名包装多挂在 XMLHttpRequest 上，用 fetch 发的请求可能压根没签名
    /// （首页接口宽松放过、翻页严格验签 → `{"status_code":0}`）。改为 **XHR 优先**让页面包装
    /// 自动补 a_bogus/msToken；若返回空响应（软拒），再用 fetch 通道补发一次（两条签名路径全覆盖）。
    private static func fetchJS(url: String) -> String {
        let tag = tagFor(url)
        return """
        (function(){
          var u='\(url)', t='\(tag)';
          try{ window.__dyTagMap=window.__dyTagMap||{}; window.__dyTagMap[u]=t; }catch(e){}
          function push(x){ try{ window.__dyCap.push({u:u+'#'+t,b:x}); }catch(e){} }
          function viaFetch(){ try{
            fetch(u,{credentials:'include'}).then(function(r){return r.text()}).then(push).catch(function(e){push('FETCHERR:'+String(e));});
          }catch(e){ push('SYNERR:'+String(e)); } }
          try{
            var x=new XMLHttpRequest();
            x.open('GET',u,true); x.withCredentials=true;
            x.onreadystatechange=function(){ if(x.readyState!==4) return;
              // v180：空响应不再用 fetch 补枪（双通道会同时回两条空响应、变体被重复消耗，
              // 且对翻页墙多发一次请求只会加速风控）。XHR 通道已验证有效。
              push(x.responseText||'');
            };
            x.onerror=function(){ viaFetch(); };
            x.send();
          }catch(e){ viaFetch(); }
        })();
        """
    }

    /// v178 页面滚动泵：真实 viewport 下把页面滚到底并派发 scroll，触发作者页自己的懒加载翻页
    /// （页面自己构造的请求，参数集与 a_bogus 全部由 jsvmp 生成，不可能验签失败）。
    private static let scrollJS = """
    (function(){try{
      var h=Math.max((document.body&&document.body.scrollHeight)||0,
                     (document.documentElement&&document.documentElement.scrollHeight)||0);
      window.scrollTo(0,h);
      try{ window.dispatchEvent(new Event('scroll',{bubbles:true})); }catch(e){}
      try{ document.dispatchEvent(new Event('scroll',{bubbles:true})); }catch(e){}
      return String(h);
    }catch(e){return 'ERR';}})();
    """

    /// v178 翻页请求排队：优先用页面原生 URL 模板（参数集 1:1），无模板才退回 myDV 参数。
    private func enqueueNextPage(variant: Int = 0) {
        let cursor = max(0, lastMaxCursor)
        if !nativePostURL.isEmpty,
           let paged = Self.nativePagedPostURL(template: nativePostURL, secUid: currentAuthorSec,
                                               cursor: cursor, altCursor: altCursor, variant: variant) {
            pendingQueue.append(paged)
            DYLog.shared.log("CAP post page (NATIVE template v\(variant)) queued cursor=\(cursor) alt=\(altCursor)")
        } else {
            let useCursor = (variant == 1 && altCursor > 0) ? altCursor : cursor
            pendingQueue.append(Self.postFetchURL(secUid: currentAuthorSec, maxCursor: useCursor))
            DYLog.shared.log("CAP post page (fallback myDV params v\(variant)) queued cursor=\(useCursor)")
        }
        postPagesFetched += 1
    }

    // MARK: - 会话管理

    /// v180：真导航到作者页，但**修好 v178 的竞态**——导航时清空队列/记时刻/重置 hook 稳定计数，
    /// drain 必须等「距导航 ≥2.5s + 新 document 连续两次 hooked=1」才发请求（v178 同秒用旧页面
    /// hooked=1 提前 fire → 128 作品作者一条都没截到）。
    /// 另：把离屏视图**加入 window 最底层**（alpha 0.01、不可交互，仍属数据泵非 UI），
    /// 让作者页列表真实布局渲染，IntersectionObserver/无限滚动才会触发页面自己的翻页请求。
    private func ensureSession(secUid: String = "") {
        if webView != nil {
            if !secUid.isEmpty, loadedAuthorSec != secUid {
                loadedAuthorSec = secUid
                nativePostURL = ""
                nativeURLLogged = false
                sessionReady = false
                readySeenAt = .distantPast
                rehooked = false
                hookedStableCount = 0
                navigationPendingAt = Date()
                pendingQueue = []          // 旧作者请求全丢；fetch() 重新排首屏
                let js = "(function(){try{location.replace('https://www.douyin.com/user/\(secUid)');}catch(e){}return 'ok';})();"
                evalJS(js, tag: "nav-author")
                DYLog.shared.event("SESSION nav author (guarded) sec=\(secUid.prefix(16))... — 等新 document hook 稳定")
            }
            return
        }
        guard let wv = DYCreateWebViewWithInject(CGRect(x: 0, y: 0, width: 1920, height: 1080), DYProfileClient.webUA, Self.hookJS) as? UIView else {
            DYLog.shared.event("SESSION FAIL: 注入式 WKWebView 创建失败")
            return
        }
        webView = wv
        if let win = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first {
            wv.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            wv.alpha = 0.01
            wv.isUserInteractionEnabled = false
            win.insertSubview(wv, at: 0)
            DYLog.shared.log("SESSION webview attached (hidden, non-interactive) for real layout")
        }
        loadedAuthorSec = secUid
        navigationPendingAt = Date()
        hookedStableCount = 0
        sessionReady = false
        readySeenAt = .distantPast
        rehooked = false
        pollCount = 0
        totalCap = 0
        lastActivityAt = Date()
        let startURL = secUid.isEmpty
            ? "https://www.douyin.com/?recommend=1"
            : "https://www.douyin.com/user/\(secUid)"
        DYLog.shared.log("SESSION boot → \(startURL.prefix(64))")
        wv.perform(NSSelectorFromString("loadRequest:"), with: NSURLRequest(url: URL(string: startURL)!))
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
        // v180：加入过 window 的隐形视图必须移除，否则被 window retain 成常驻幽灵层
        if let wv = webView, wv.superview != nil { wv.removeFromSuperview() }
        webView = nil
        loadedAuthorSec = ""
        seenURLLogged = []
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
            // v181 全端点透视日志（去重）：确认页面作者页滚动到底走哪个端点
            for s in (diag["seen"] as? [String] ?? []) {
                let key = String(s.prefix(120))
                if self.seenURLLogged.insert(key).inserted {
                    DYLog.shared.log("SESSION page-url \(s.prefix(220))")
                }
            }
            if !hooked, !self.rehooked {
                self.rehooked = true
                DYLog.shared.log("SESSION[\(tag)] hooked=0 → evaluateJavaScript 补装 hook")
                self.evalJS(Self.hookJS, tag: "rehook")
            }
            // 会话就绪判定（v180 竞态护栏）：导航/首次加载后必须等 ≥2.5s 且
            // **新 document 连续两次 hooked=1** 才放行 —— 否则会像 v178 那样用旧页面状态提前 fire。
            if !self.sessionReady, hooked {
                let sinceNav = Date().timeIntervalSince(self.navigationPendingAt)
                self.hookedStableCount += 1
                if sinceNav >= 2.5, self.hookedStableCount >= 2 {
                    self.sessionReady = true
                    DYLog.shared.event("SESSION ready (stable hook #\(self.hookedStableCount), +\(String(format: "%.1f", sinceNav))s) → 队列 \(self.pendingQueue.count) 条待发")
                }
            } else if !hooked {
                self.hookedStableCount = 0
            }
            // 发队列（v175 提速：每 tick 连发 2 条；v176：_push 指令 + postcap 节流）
            if self.sessionReady, !self.pendingQueue.isEmpty {
                var fired = 0
                while fired < 2, let item = self.pendingQueue.first {
                    if item.hasPrefix("_push:") {
                        self.pendingQueue.removeFirst()
                        let path = String(item.dropFirst(6))
                        let js = "(function(){try{history.replaceState(null,'','https://www.douyin.com\(path)');}catch(e){}return String(location.href);})();"
                        self.evalJS(js, tag: "push:\(path)")
                        DYLog.shared.log("SESSION page URL → https://www.douyin.com\(path) (referer 对齐 myDV u11.F0)")
                        continue
                    }
                    if Self.tagFor(item) == "postcap" {
                        let now = Date()
                        if now < self.postEarliestFireAt || now.timeIntervalSince(self.lastPostFireAt) < 3 {
                            break   // 翻页 ≥3s 节流（myDV 用户滚动翻页天然有间隔）
                        }
                        self.lastPostFireAt = now
                        self.postEarliestFireAt = .distantPast
                    }
                    self.pendingQueue.removeFirst()
                    self.lastActivityAt = Date()
                    self.totalCap += 1
                    let tagWord = Self.tagFor(item)
                    DYLog.shared.log("SESSION fire \(tagWord) → \(item.prefix(100))")
                    self.evalJS(Self.fetchJS(url: item), tag: tagWord)
                    fired += 1
                }
            }
            // 分发响应（v178：标记只在 u 末尾的 #tag；页面原生请求无 tag，一律走 page-req 累积通道）
            for item in cap {
                let u = item["u"] as? String ?? "?"
                let b = item["b"] as? String ?? ""
                let tag = Self.tagFrom(u)
                if u.contains("aweme/post") {
                    self.noteNativePostURL(u)
                    // v180 验收关键证据：无 tag = 页面自己发的请求；非零游标 = 页面原生翻页
                    if tag.isEmpty, u.contains("max_cursor="), !u.contains("max_cursor=0&"),
                       !u.contains("max_cursor=0#") {
                        DYLog.shared.event("SESSION PAGE-NATIVE PAGING u=\(u.prefix(180))")
                    }
                }
                if tag.isEmpty {
                    DYLog.shared.log("SESSION page-req len=\(b.count) u=\(u.prefix(300))")
                    if u.contains("aweme/post") {
                        self.lastActivityAt = Date()
                        self.handleWorks(b, allowPaging: false)
                    } else if u.contains("user/profile") {
                        self.lastActivityAt = Date()
                        self.handleProfile(b)
                    }
                    continue
                }
                self.lastActivityAt = Date()
                switch tag {
                case "profcap":
                    DYLog.shared.event("CAP profcap len=\(b.count)")
                    self.handleProfile(b)
                case "postcap":
                    DYLog.shared.event("CAP postcap len=\(b.count)")
                    self.handleWorks(b, allowPaging: true)
                case "detailcap":
                    DYLog.shared.event("CAP detailcap len=\(b.count)")
                    self.handleDetail(b)
                default:
                    DYLog.shared.event("CAP mixcap len=\(b.count)")
                    self.handleMix(b)
                }
            }
        }
    }

    private static func tagFrom(_ u: String) -> String {
        for t in ["profcap", "postcap", "detailcap", "mixcap"] where u.hasSuffix("#" + t) { return t }
        return ""
    }

    /// v178 记录页面包装后真实发出的原生 aweme/post URL（hook 不再 slice 截断），
    /// 分片打日志备查，并作为翻页参数模板（nativePagedPostURL）。
    private func noteNativePostURL(_ u: String) {
        var clean = u
        let t = Self.tagFrom(clean)
        if !t.isEmpty { clean = String(clean.dropLast(t.count + 1)) }
        guard clean.count > 120, clean.contains("aweme/post") else { return }
        // 页面 jsvmp 包装后的 URL 带 a_bogus/msToken —— 优先作为模板；
        // 我们自拼的干净 URL 只作兜底（否则又回到连败 3 版的老路）。
        let signed = clean.contains("a_bogus") || clean.contains("msToken")
        let isFirst = clean.contains("max_cursor=0")
        let better = signed && !nativePostURL.contains("a_bogus")
        if nativePostURL.isEmpty || better || (isFirst && signed && !nativePostURL.contains("max_cursor=0")) {
            nativePostURL = clean
            if !nativeURLLogged || better {
                nativeURLLogged = true
                let chars = Array(clean.prefix(1000))
                var i = 0, part = 0
                while i < chars.count {
                    let end = min(i + 100, chars.count)
                    DYLog.shared.log("NATIVE POST URL[\(part)]=\(String(chars[i..<end]))")
                    i = end; part += 1
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
        self.cachedProfile = u
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.worksCaptureDidCapture(profile: u)
        }
    }

    /// 解析 aweme/post 响应（grab slim 或裸 JSON 兜底）→ 累积 → delegate → hasMore 自动翻页
    private func handleWorks(_ body: String, allowPaging: Bool = true) {
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
                else if let mc = obj["maxCursor"] as? Int, mc > 0 { nextCursor = mc; altCursor = mc }
                if let mc = obj["maxCursor"] as? Int, mc > 0 { altCursor = mc }
                // v181 时间分组探测（若非空，下一版可走 time_list_query=1 按月取）
                if let tl = obj["tl"] as? String, !tl.isEmpty {
                    DYLog.shared.log("CAP post TIME LIST \(tl.prefix(500))")
                }
                mixName = obj["mixName"] as? String ?? ""
            } else if let list = obj["aweme_list"] as? [[String: Any]] {
                // 裸 JSON 兜底（grab 端 JSON.parse 失败/超长响应）
                works = Self.parseFull(list)
                hasMore = (obj["has_more"] as? Int ?? 0) != 0
                if let c = obj["cursor"] as? Int, c > 0 { nextCursor = c }
                else if let mc = obj["max_cursor"] as? Int, mc > 0 { nextCursor = mc; altCursor = mc }
                if let mc = obj["max_cursor"] as? Int, mc > 0 { altCursor = mc }
                if let mi = obj["mix_info"] as? [String: Any] { mixName = mi["mix_name"] as? String ?? "" }
            }
        }
        DYLog.shared.event("CAP post ok n=\(works.count) hasMore=\(hasMore ? 1 : 0) cursor=\(nextCursor) maxCursor=\(altCursor)")
        guard !works.isEmpty else {
            // v180 真机实锤「翻页墙」：max_cursor=0 → 完整 20 条 / 2.7MB；
            // 任何 max_cursor!=0（含换游标值、换 cursor 键、need_time_list=0 三变体）→ 17 字节
            // {"status_code":0}。与 HANDOVER §5.3 的 aweme/post「200 空=签名/会话信任墙」同源。
            // → 彻底停止自拼翻页请求（继续发只会被风控），把翻页交给页面自己的懒加载。
            DYLog.shared.event("CAP post EMPTY body=\(body.prefix(120)) — paging wall")
            guard allowPaging else { return }
            if Date().timeIntervalSince(lastVariantAt) > 8 {
                lastVariantAt = Date()
                self.evalJS(Self.scrollJS, tag: "wall-scroll")
                DYLog.shared.event("CAP post → hand over to page-native scroll; keep hasMore total=\(self.capturedWorks.count)")
            }
            return
        }
        self.postEmptyRetries = 0
        let known = Set(capturedWorks.map { $0.id })
        let fresh = works.filter { !known.contains($0.id) }
        capturedHasMore = hasMore
        if nextCursor > lastMaxCursor { lastMaxCursor = nextCursor }
        if !fresh.isEmpty {
            capturedWorks.append(contentsOf: fresh)
            let total = capturedWorks.count
            DYLog.shared.event("CAP works accumulated +\(fresh.count) → \(total) hasMore=\(hasMore ? 1 : 0)")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.worksCaptureDidCapture(works: self.capturedWorks, hasMore: self.capturedHasMore)
            }
        }
        // v180：**不再自拼下一页**（翻页墙 100% 软拒，实锤三变体全灭）。
        // 更多作品完全由页面作者页自己的无限滚动请求提供 —— 那些请求由页面 jsvmp
        // 自己拼参数、自己签名，是唯一可能穿过信任墙的形态；hook 会经 page-req 通道累积。
        if allowPaging, hasMore, !fresh.isEmpty {
            DYLog.shared.log("CAP post hasMore=1 → wait for page-native paging (no self-issued page)")
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
        // 切到合集页再打 mix/aweme，referer 对齐 myDV u11.o
        pendingQueue.insert("_push:/collection/\(mid)", at: 0)
        pendingQueue.insert(Self.mixFetchURL(mixId: mid), at: 1)
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
      var diag={rs:'',href:'',hooked:false,n:cap.length,seen:[]};
      // v181 全端点透视：页面自己发的 web API 端点（翻页可能走我们没拦的路径）
      try{ diag.seen=window.__dySeenUrls.splice(0); }catch(e){}
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
      if(window.__dyHooked) return; window.__dyHooked=true; window.__dyCap=[]; window.__dySeenUrls=[];
      function grab(u,b){ try{
        if(!u||!b) return;
        var s=String(u);
        if(s.indexOf('aweme/post')<0&&s.indexOf('series/')<0&&s.indexOf('mix/')<0&&s.indexOf('user/profile')<0&&s.indexOf('aweme/detail')<0) return;
        var body=(typeof b==='string')?b:JSON.stringify(b);
        // v178：标记不进实际 URL（query/fragment 都会破坏页面签名），从 JS 本地映射取；
        // aweme/post 保留完整 URL（最多 1200 字符）→ Swift 侧作为翻页参数模板 1:1 照抄。
        var hi=s.indexOf('#'), tag=(hi>=0)?s.slice(hi):'';
        if(!tag&&window.__dyTagMap){ var mt=window.__dyTagMap[s]||window.__dyTagMap[s.split('#')[0]]; if(mt)tag='#'+mt; }
        var us=(s.indexOf('aweme/post')>=0)?(s.slice(0,1200)+tag):(s.slice(0,120)+tag);
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
            // v181：need_time_list=1 的首屏响应可能带按年月分组的 time_list
            // （抖音作者页"按时间筛选"）；若存在，可用 time_list_query=1 按月取数据绕过翻页墙。
            var tl=''; try{ if(j.time_list) tl=JSON.stringify(j.time_list).slice(0,1500); }catch(e){}
            window.__dyCap.push({u:us,b:JSON.stringify({works:slim,hasMore:(j.has_more||0),maxCursor:(j.max_cursor||0),cursor:(j.cursor||0),mixName:mn,tl:tl})});
            return;
          }
        }
        window.__dyCap.push({u:us,b:body.slice(0,300000)});
      }catch(e){} }
      var xo=XMLHttpRequest.prototype.open, xs=XMLHttpRequest.prototype.send;
      // v181 全端点透视：记录页面（含我们自己的 XHR）发出的所有 /aweme/v1/web/ URL，
      // 用于确认作者页滚动到底走的是哪个端点（可能根本不是 aweme/post）。去重、限 60 条/tick。
      XMLHttpRequest.prototype.open=function(m,u){
        try{ var su=String(u); if(su.indexOf('/aweme/v1/web/')>=0){
          window.__dySeenUrls=window.__dySeenUrls||[];
          if(window.__dySeenUrls.length<60) window.__dySeenUrls.push(su.slice(0,220));
        } }catch(e){}
        this.__u=u; return xo.apply(this,arguments); };
      XMLHttpRequest.prototype.send=function(){ var x=this; this.__u=String(this.__u||'');
        this.addEventListener('readystatechange',function(){ if(x.readyState===4){ try{ var t=x.responseType; if(!t||t==='text'||t==='json'){ grab(x.__u,(t==='json')?x.response:x.responseText); } }catch(e){} } });
        return xs.apply(this,arguments); };
      var of=window.fetch;
      if(of){ window.fetch=function(){ var a=arguments,u=(a[0]&&a[0].url)||a[0]; u=String(u);
        return of.apply(this,arguments).then(function(r){ try{ var c=r.clone(); c.text().then(function(t){ grab(u,t); }).catch(function(){}); }catch(e){} return r; }); }; }
      // v178 页面内滚动泵：作者页路径下每 2.5s 滚到底 + 派发 scroll（1x1 viewport 时代永不触发，
      // 现为 1920x1080 真实 viewport）。页面自己的懒加载翻页请求由自身 jsvmp 签名，最可靠。
      try{ setInterval(function(){ try{
        if(String(location.pathname).indexOf('/user/')!==0) return;
        var h=Math.max((document.body&&document.body.scrollHeight)||0,
                       (document.documentElement&&document.documentElement.scrollHeight)||0);
        window.scrollTo(0,h);
        try{ window.dispatchEvent(new Event('scroll',{bubbles:true})); }catch(e){}
        try{ document.dispatchEvent(new Event('scroll',{bubbles:true})); }catch(e){}
      }catch(e){} },2500); }catch(e){}
    })();
    """
}
