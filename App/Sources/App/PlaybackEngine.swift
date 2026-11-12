import Foundation
import Combine

/// 原生播放引擎：持有有序视频直链 + 当前索引，驱动 AVPlayer。
/// 数据源：隐藏 WebView 的 hook 抽到 play_addr.url_list 后经 WebKitShell 注入。
/// 无限刷：接近末尾自动回调 onNeedMore 让页面翻页；整批过期/连续失败回调 onRefresh 重拉。
/// 焦点意图：本类无 UI；上/下键切 prev/next 在 DYPlayerViewController 处理。
final class PlaybackEngine: ObservableObject {
    static let shared = PlaybackEngine()

    @Published var urls: [URL] = []
    @Published var index: Int = 0

    /// 直链批次拉取时间（用于过期判断）
    private(set) var fetchedAt: Date = .distantPast
    /// 已消费的 aweme id（刷新后按 id 对齐位置）
    private var awemeOrder: [String] = []
    private var currentAwemeId: String = ""

    /// 页面翻页回调（接近末尾时触发，由 WebKitShell 注入）
    var onNeedMore: (() -> Void)?
    /// 整批过期/连续失败回调（由 WebKitShell 注入，触发页面重拉全批）
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

    /// 已消费（当前及之前）的 aweme id——feed 直连翻页时作 presented_ids 排除重复推荐。
    var consumedIds: [String] {
        Array(awemeOrder.prefix(max(0, min(index + 1, awemeOrder.count))))
    }

    /// 统一合并入口（泵 VIDS 与原生直连两个来源共用）：
    /// 按 aweme_id 去重保序；replaceExisting=true 时用新 URL 替换已有（过期重拉）。
    /// autoPlay=true 时跳到 index 0（首批）；否则保持当前 index（翻页追加）；
    /// refresh=true 时按 id 对齐回原位置。
    func merge(ids: [String], urls newUrls: [URL], replaceExisting: Bool, autoPlay: Bool, refresh: Bool) {
        let previousAwemeId = currentAwemeId
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
        fetchedAt = Date()
        consecutiveFailures = 0
        if refresh, !previousAwemeId.isEmpty, let pos = awemeOrder.firstIndex(of: previousAwemeId) {
            index = pos
        } else if autoPlay {
            index = 0
        }
        DYLog.shared.log("ENGINE merge total=\(mergedUrls.count) index=\(index) replace=\(replaceExisting) auto=\(autoPlay)")
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
