import Foundation
import Combine

/// 视频源（v135 设置面板切换）：mobile=移动端推荐(aweme.snssdk.com protobuf)；web=抖音精选(www.douyin.com tab/feed JSON)；
/// tiktok=国际版 TikTok(离屏 WebView 数据泵 hook recommend/item_list，v223)
enum DYFeedSource: String {
    case mobile
    case web
    case tiktok
}

/// 单条视频的展示信息（v143 PC 版 UI：右轨计数 + 左下作者/文案）。
/// 字段号 wire 实测（dev 探针 _tmp/aweme_fields_probe.js，双样本一致）：
/// mobile proto: desc=aweme f2, hashtags=f459, author=f4(f3=昵称, f5/6/7=头像), statistics=f10(f3=赞 f2=评论 f6=分享 f11=收藏)
struct DYVideoInfo {
    var nickname: String = ""
    var avatarUrl: String = ""
    var digg: Int = 0
    var comment: Int = 0
    var share: Int = 0
    var collect: Int = 0
    var desc: String = ""
    var hashtags: String = ""
    /// 发布时间文本（v144：昵称后展示；解析期格式化好）
    var createTimeText: String = ""
    /// 合集识别（v145：mobile=aweme f14 子消息存在（wire 观测：内含合集名 f5）；web=mix_info）
    var isMix: Bool = false
    var mixName: String = ""
    /// v172 合集 id（mobile=f14 f6 wire 实测；web=mix_info.mix_id）——快捷面板"合集"实装的数据钥匙
    var mixId: String = ""
    /// 作者 sec_uid（v153 主页用；mobile=author f191，web=author.sec_uid）
    var secUid: String = ""
}

/// 原生播放引擎：持有有序视频直链 + 当前索引，驱动 AVPlayer。
/// 数据源：DYFeedClient（mobile=myDV 移动端 /aweme/v2/feed/ protobuf 直连；v135 web=抖音精选 /aweme/v1/web/tab/feed/ JSON）
/// 无限刷：接近末尾自动回调 onNeedMore 让 DYFeedClient 翻页（refresh_index 递增）；
///         整批过期/连续失败回调 onRefresh 重拉当前页。回调由 DYTVApp 接线，不经任何 WebView。
/// 焦点意图：本类无 UI；上/下键切 prev/next 在 DYPlayerViewController 处理。
final class PlaybackEngine: ObservableObject {
    static let shared = PlaybackEngine()

    /// 当前视频源（PlayerManager 按 source 选播放请求头：mobile UA/Cookie vs web UA/Referer/ttwid）
    var source: DYFeedSource = .mobile

    @Published var urls: [URL] = []
    @Published var index: Int = 0
    /// 主 feed 首帧已渲染（v195：NativePlayerView watchTick 检测居中 cell playerLayer.isReadyForDisplay）
    /// 启动加载视频 overlay 观察它——首帧到了交叉淡化掉加载视频，露出主 feed（替代启动黑屏）
    @Published var firstFrameReady = false
    /// 每条视频的原始 video 子消息 bytes（index→bytes）
    private var rawVideos: [Int: [UInt8]] = [:]
    /// 每条视频的备用重定向直链（index→URL）：/aweme/v1/play 端点——URL 本身不带时效签名，
    /// 播放时请求由服务器现场 302 生成新鲜 CDN 直链（AVPlayer 自动跟随）。
    /// 静态直链（douyinvod，URL 内嵌过期签名）超龄时的唯一可靠"真新鲜"来源。
    private var redirectUrls: [Int: URL] = [:]
    /// 每条静态直链的生成时刻（index→Date，≈该批 feed 抓取时刻）——acquire 判断静态直链是否可能已过期
    private var mintedAt: [Int: Date] = [:]
    /// 每条视频时长 ms（index→ms，弹幕请求 end_time/duration 用）
    private var durations: [Int: Int] = [:]
    /// 每条视频展示信息（v143 PC 版 UI：昵称/头像/计数/文案）
    private var infos: [Int: DYVideoInfo] = [:]

    /// 直链批次拉取时间（用于过期判断）
    private(set) var fetchedAt: Date = .distantPast
    /// 已消费的 aweme id（刷新后按 id 对齐位置）
    private var awemeOrder: [String] = []
    private var currentAwemeId: String = ""

    /// 翻页回调（接近末尾时触发，由 DYTVApp 接到 DYFeedClient.fetchPage）
    var onNeedMore: (() -> Void)?
    /// 整批过期/连续失败回调（触发重拉当前页，由 DYTVApp 接到 DYFeedClient.refetchCurrent）
    var onRefresh: (() -> Void)?

    private var lastNeedMoreAt: Date = .distantPast
    private var lastRefreshAt: Date = .distantPast
    private var consecutiveFailures = 0
    private let staleInterval: TimeInterval = 240      // 4 分钟视为整批过期
    private let needMoreThreshold = 7                   // 剩余 ≤7 条时提前翻页（第 35/41 条即触发，无缝衔接）
    private let refreshCooldown: TimeInterval = 5       // 刷新/翻页冷却，防刷屏

    var currentURL: URL? {
        urls.indices.contains(index) ? urls[index] : nil
    }

    var count: Int { urls.count }

    /// 源切换时清空全部状态（urls 空 → 控制器 reloadIfNeeded 走空态重置；旧 player 由下次 prepare 驱逐）
    func reset() {
        urls = []
        index = 0
        rawVideos = [:]
        redirectUrls = [:]
        mintedAt = [:]
        durations = [:]
        infos = [:]
        awemeOrder = []
        currentAwemeId = ""
        fetchedAt = .distantPast
        consecutiveFailures = 0
        worksSegment = nil
        DYLog.shared.log("ENGINE reset (source switch)")
    }

    /// 取 index 的原始 video 子消息 bytes。
    func rawVideo(at index: Int) -> [UInt8]? {
        rawVideos[index]
    }

    /// 取 index 的重定向直链（静态直链过期时的播放来源）。
    func redirectURL(at index: Int) -> URL? {
        redirectUrls[index]
    }

    /// 静态直链年龄（秒）；无记录视为刚生成（0）。
    func urlAge(at index: Int) -> TimeInterval {
        guard let t = mintedAt[index] else { return 0 }
        return Date().timeIntervalSince(t)
    }

    /// 取 index 的 awemeId（弹幕请求 item_id/group_id 用）。
    func awemeId(at index: Int) -> String? {
        awemeOrder.indices.contains(index) ? awemeOrder[index] : nil
    }

    /// 取 index 的视频时长 ms（弹幕请求 end_time/duration 用；无记录 0）。
    func durationMs(at index: Int) -> Int {
        durations[index] ?? 0
    }

    /// 取 index 的展示信息（PC 版 UI：昵称/计数/文案）。
    func videoInfo(at index: Int) -> DYVideoInfo? {
        infos[index]
    }

    /// 已消费（当前及之前）的 aweme id——feed 直连翻页时作 presented_ids 排除重复推荐。
    var consumedIds: [String] {
        Array(awemeOrder.prefix(max(0, min(index + 1, awemeOrder.count))))
    }

    /// 统一合并入口（泵 VIDS 与原生直连两个来源共用）：
    /// 按 aweme_id 去重保序；replaceExisting=true 时用新 URL 替换已有（过期重拉）。
    /// autoPlay=true 时跳到 index 0（首批）；否则保持当前 index（翻页追加）；
    /// refresh=true 时按 id 对齐回原位置。
    func merge(ids: [String], urls newUrls: [URL], replaceExisting: Bool, autoPlay: Bool, refresh: Bool, allRawVideos: [[UInt8]]? = nil, allRedirectUrls: [URL?]? = nil, allDurations: [Int]? = nil, allInfos: [DYVideoInfo]? = nil) {
        let previousAwemeId = currentAwemeId
        let oldCount = awemeOrder.count
        var mergedIds = awemeOrder
        var mergedUrls = self.urls
        var position = [String: Int]()
        for (i, id) in awemeOrder.enumerated() { position[id] = i }
        for (i, id) in ids.enumerated() {
            if let p = position[id] {
                if replaceExisting { mergedUrls[p] = newUrls[i] }
            } else {
                position[id] = mergedIds.count
                mergedIds.append(id)
                mergedUrls.append(newUrls[i])
            }
        }
        awemeOrder = mergedIds
        self.urls = mergedUrls
        // 存原始 video bytes（按最终 position）
        if let raws = allRawVideos {
            for (i, id) in ids.enumerated() {
                if let p = position[id], i < raws.count {
                    rawVideos[p] = raws[i]
                }
            }
        }
        // 存重定向直链 + 静态直链生成时刻（本批 merge 时刻；仅新增/替换的条目刷新时刻，去重旧条目保留原时刻）
        let now = Date()
        for (i, id) in ids.enumerated() {
            guard let p = position[id] else { continue }
            if p >= oldCount || replaceExisting { mintedAt[p] = now }
            if let redirects = allRedirectUrls, i < redirects.count {
                redirectUrls[p] = redirects[i]
            }
            if let durs = allDurations, i < durs.count {
                durations[p] = durs[i]
            }
            if let pinfos = allInfos, i < pinfos.count {
                infos[p] = pinfos[i]
            }
        }
        fetchedAt = Date()
        consecutiveFailures = 0
        if refresh, !previousAwemeId.isEmpty, let pos = awemeOrder.firstIndex(of: previousAwemeId) {
            index = pos
        } else if autoPlay {
            index = 0
        }
        let redirectCount = allRedirectUrls?.compactMap { $0 }.count ?? 0
        DYLog.shared.log("ENGINE merge total=\(mergedUrls.count) index=\(index) replace=\(replaceExisting) auto=\(autoPlay) redirect=\(redirectCount)")
    }

    /// 注入一批有序直链。isNewBatch=true（首次/翻页新增）时自动播 index 0；
    /// isRefresh=true（过期重拉）时按 aweme id 对齐回原位置。
    func setURLs(_ new: [URL], awemeIds: [String], isNewBatch: Bool, isRefresh: Bool) {
        let previousAwemeId = currentAwemeId
        urls = new
        awemeOrder = awemeIds
        fetchedAt = Date()
        consecutiveFailures = 0

        if isRefresh, !previousAwemeId.isEmpty,
           let pos = awemeOrder.firstIndex(of: previousAwemeId) {
            index = pos // 刷新：对齐回原视频
        } else if isNewBatch {
            index = 0   // 首批/翻页：自动播第一条（解"要手动按"）
        }
        DYLog.shared.log("ENGINE setURLs count=\(new.count) index=\(index) refresh=\(isRefresh)")
    }

    /// v174 作品/合集段标记（用户拍板的点播语义）：
    /// 未操作=自动刷作者作品段/合集段，刷完自动回归 feed（段插在当前播放位之后）；
    /// 操作=快捷面板「回到推荐」立即 removeWorksSegment 推回正常视频流。
    struct WorksSegment { let anchor: Int; let start: Int; let count: Int }
    private(set) var worksSegment: WorksSegment?

    /// v174 段插入式重建（v172 版本回归）：作品段插在当前播放位之后 = 已看 feed 前缀 + 作品段 + feed 剩余。
    /// 已有段时先移除旧段再插新段（换作者/换合集场景）。返回选中作品的最终位置。
    /// allDurations/allInfos 与 ids 同下标对位。
    @discardableResult
    func insertWorks(ids: [String], urls newUrls: [URL], allDurations: [Int]?, allInfos: [DYVideoInfo]?, selectedId: String) -> Int {
        if worksSegment != nil { removeWorksSegment() }
        let cur = index
        let existing = Set(awemeOrder)
        var wIds: [String] = [], wUrls: [URL] = [], wDurs: [Int] = [], wInfos: [DYVideoInfo] = []
        for (i, id) in ids.enumerated() where !existing.contains(id) {
            wIds.append(id)
            wUrls.append(newUrls[i])
            wDurs.append(allDurations?[i] ?? 0)
            wInfos.append(allInfos?[i] ?? DYVideoInfo())
        }
        // 选中作品若已在 feed 里（当前作者=正在看的作者），直接跳到它的 feed 位置
        if wIds.isEmpty || (!wIds.contains(selectedId) && existing.contains(selectedId)) {
            let pos = awemeOrder.firstIndex(of: selectedId) ?? cur
            index = pos
            currentAwemeId = awemeOrder.indices.contains(pos) ? awemeOrder[pos] : ""
            DYLog.shared.log("ENGINE insertWorks skip (selected already in feed) pos=\(pos)")
            return pos
        }
        guard !wIds.isEmpty else { return cur }
        let insertAt = cur + 1
        let oldCount = awemeOrder.count
        let newCount = oldCount + wIds.count
        // 位置映射：p <= cur → p；p > cur → p + wIds.count；works 占 insertAt..insertAt+wIds.count-1
        func newPos(_ p: Int) -> Int { p <= cur ? p : p + wIds.count }
        var newRaw: [Int: [UInt8]] = [:]
        var newRedir: [Int: URL] = [:]
        var newMinted: [Int: Date] = [:]
        var newDur: [Int: Int] = [:]
        var newInfo: [Int: DYVideoInfo] = [:]
        for (p, v) in rawVideos { newRaw[newPos(p)] = v }
        for (p, v) in redirectUrls { newRedir[newPos(p)] = v }
        for (p, v) in mintedAt { newMinted[newPos(p)] = v }
        for (p, v) in durations { newDur[newPos(p)] = v }
        for (p, v) in infos { newInfo[newPos(p)] = v }
        let now = Date()
        for i in 0..<wIds.count {
            let p = insertAt + i
            newMinted[p] = now   // works 无 raw bytes（web JSON 直链），不进 rawVideos
            newDur[p] = wDurs[i]
            newInfo[p] = wInfos[i]
        }
        var newIds: [String] = []
        var newUrls2: [URL] = []
        for i in 0..<newCount {
            if i < insertAt {
                newIds.append(awemeOrder[i]); newUrls2.append(urls[i])
            } else if i < insertAt + wIds.count {
                let wi = i - insertAt
                newIds.append(wIds[wi]); newUrls2.append(wUrls[wi])
            } else {
                let oi = i - wIds.count
                newIds.append(awemeOrder[oi]); newUrls2.append(urls[oi])
            }
        }
        awemeOrder = newIds
        self.urls = newUrls2
        rawVideos = newRaw
        redirectUrls = newRedir
        mintedAt = newMinted
        durations = newDur
        infos = newInfo
        fetchedAt = Date()
        consecutiveFailures = 0
        let pos = wIds.firstIndex(of: selectedId).map { insertAt + $0 } ?? cur
        index = pos
        currentAwemeId = awemeOrder.indices.contains(pos) ? awemeOrder[pos] : ""
        worksSegment = WorksSegment(anchor: cur, start: insertAt, count: wIds.count)
        DYLog.shared.log("ENGINE insertWorks total=\(newCount) works=\(wIds.count) insertAt=\(insertAt) pos=\(pos) anchor=\(cur)")
        return pos
    }

    /// v174 用户操作「回到推荐」：移除作品/合集段，推回正常视频流（= 锚点视频的下一格）。
    /// 返回应跳转的 feed 位置。
    /// ⚠️ v175 崩溃修复（v174 真机实锤「回到推荐」闪退）：段区间 key 必须先剔除再重映射，
    /// 否则 oldPos 对段内 key 产生负数/重复 key → Dictionary(uniqueKeysWithValues:) fatal。
    @discardableResult
    func removeWorksSegment() -> Int {
        guard let seg = worksSegment else { return index }
        let (anchor, start, count) = (seg.anchor, seg.start, seg.count)
        func oldPos(_ p: Int) -> Int { p <= anchor ? p : p - count }
        func remap(_ dict: [Int: Int]) -> [Int: Int] {
            Dictionary(uniqueKeysWithValues: dict.compactMap { (p, v) -> (Int, Int)? in
                (p >= start && p < start + count) ? nil : (oldPos(p), v)
            })
        }
        rawVideos = Dictionary(uniqueKeysWithValues: rawVideos.compactMap { (p, v) -> (Int, [UInt8])? in
            (p >= start && p < start + count) ? nil : (oldPos(p), v)
        })
        redirectUrls = Dictionary(uniqueKeysWithValues: redirectUrls.compactMap { (p, v) -> (Int, URL)? in
            (p >= start && p < start + count) ? nil : (oldPos(p), v)
        })
        mintedAt = Dictionary(uniqueKeysWithValues: mintedAt.compactMap { (p, v) -> (Int, Date)? in
            (p >= start && p < start + count) ? nil : (oldPos(p), v)
        })
        durations = remap(durations)
        infos = Dictionary(uniqueKeysWithValues: infos.compactMap { (p, v) -> (Int, DYVideoInfo)? in
            (p >= start && p < start + count) ? nil : (oldPos(p), v)
        })
        var newIds: [String] = []
        var newUrls: [URL] = []
        for i in 0..<urls.count where !(i >= start && i < start + count) {
            newIds.append(awemeOrder[i]); newUrls.append(urls[i])
        }
        awemeOrder = newIds
        urls = newUrls
        worksSegment = nil
        let jump = min(anchor + 1, max(0, awemeOrder.count - 1))
        index = jump
        currentAwemeId = awemeOrder.indices.contains(jump) ? awemeOrder[jump] : ""
        DYLog.shared.log("ENGINE removeWorks anchor=\(anchor) count=\(count) jump=\(jump) total=\(awemeOrder.count)")
        return jump
    }

    /// 当前 index 是否落在作品/合集段内（快捷面板「回到推荐」项的显示条件）
    var isInWorksSegment: Bool {
        guard let seg = worksSegment else { return false }
        return index >= seg.start && index < seg.start + seg.count
    }

    func next() {
        // 接近末尾 → 触发翻页（冷却防刷屏）
        if index >= urls.count - needMoreThreshold {
            triggerNeedMore()
        }
        guard index < urls.count - 1 else {
            triggerNeedMore()
            return
        }
        index += 1
        currentAwemeId = awemeOrder.indices.contains(index) ? awemeOrder[index] : ""
        DYLog.shared.log("ENGINE next -> index=\(index)")
    }

    func prev() {
        guard index > 0 else { return }
        index -= 1
        currentAwemeId = awemeOrder.indices.contains(index) ? awemeOrder[index] : ""
        DYLog.shared.log("ENGINE prev -> index=\(index)")
    }

    /// 当前 URL 是否已过期（整批超时）。
    var isStale: Bool {
        Date().timeIntervalSince(fetchedAt) > staleInterval
    }

    /// 播放失败时调用：连续失败达到阈值或整批过期 → 触发刷新。
    func reportFailure() {
        consecutiveFailures += 1
        if consecutiveFailures >= 2 || isStale {
            triggerRefresh()
        }
    }

    func triggerNeedMore() {
        guard Date().timeIntervalSince(lastNeedMoreAt) > refreshCooldown else { return }
        lastNeedMoreAt = Date()
        DYLog.shared.log("ENGINE needMore (index=\(index) count=\(urls.count))")
        onNeedMore?()
    }

    func triggerRefresh() {
        guard Date().timeIntervalSince(lastRefreshAt) > refreshCooldown else { return }
        lastRefreshAt = Date()
        consecutiveFailures = 0
        DYLog.shared.log("ENGINE refresh (stale=\(isStale))")
        onRefresh?()
    }

    /// 从 hook 回传的 "aweme_ID >> url" 行里提取，只保留 douyinvod CDN 直链，
    /// 丢弃必失败的 /aweme/v1/play/ 端点（403 no-permission → 黑屏）。
    static func extract(from videoLines: [String]) -> (urls: [URL], awemeIds: [String]) {
        var urlsOut: [URL] = []
        var idsOut: [String] = []
        var seenAweme = Set<String>()
        for line in videoLines {
            let parts = line.components(separatedBy: " >> ")
            guard parts.count == 2 else { continue }
            let raw = parts[1].trimmingCharacters(in: .whitespaces)
            guard !raw.contains("/aweme/v1/play/"), let url = URL(string: raw) else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            guard !seenAweme.contains(key) else { continue }
            seenAweme.insert(key)
            urlsOut.append(url)
            idsOut.append(key)
        }
        return (urlsOut, idsOut)
    }
}
