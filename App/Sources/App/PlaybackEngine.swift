import Foundation
import Combine

/// 视频源（v135 设置面板切换）：mobile=移动端推荐(aweme.snssdk.com protobuf)；web=抖音精选(www.douyin.com tab/feed JSON)
enum DYFeedSource: String {
    case mobile
    case web
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
        awemeOrder = []
        currentAwemeId = ""
        fetchedAt = .distantPast
        consecutiveFailures = 0
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

    /// 已消费（当前及之前）的 aweme id——feed 直连翻页时作 presented_ids 排除重复推荐。
    var consumedIds: [String] {
        Array(awemeOrder.prefix(max(0, min(index + 1, awemeOrder.count))))
    }

    /// 统一合并入口（泵 VIDS 与原生直连两个来源共用）：
    /// 按 aweme_id 去重保序；replaceExisting=true 时用新 URL 替换已有（过期重拉）。
    /// autoPlay=true 时跳到 index 0（首批）；否则保持当前 index（翻页追加）；
    /// refresh=true 时按 id 对齐回原位置。
    func merge(ids: [String], urls newUrls: [URL], replaceExisting: Bool, autoPlay: Bool, refresh: Bool, allRawVideos: [[UInt8]]? = nil, allRedirectUrls: [URL?]? = nil, allDurations: [Int]? = nil) {
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
