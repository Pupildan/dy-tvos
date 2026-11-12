import Foundation
import Combine

/// 原生播放引擎：持有有序视频直链 + 当前索引，驱动 AVPlayer。
/// 数据源：隐藏 WebView 的 hook 抽到 play_addr.url_list 后经 WebKitShell 注入。
/// 焦点意图：本类无 UI；上/下键切 prev/next 在 NativePlayerViewController 处理。
final class PlaybackEngine: ObservableObject {
    static let shared = PlaybackEngine()

    @Published var urls: [URL] = []
    @Published var index: Int = 0

    var currentURL: URL? {
        urls.indices.contains(index) ? urls[index] : nil
    }

    var count: Int { urls.count }

    /// 注入一批有序直链（已在 Swift 侧按 aweme 顺序、优先 douyinvod .mp4 去重排序）。
    func setURLs(_ new: [URL]) {
        urls = new
        index = 0
        DYLog.shared.log("ENGINE setURLs count=\(new.count)")
    }

    func next() {
        guard index < urls.count - 1 else { return }
        index += 1
        DYLog.shared.log("ENGINE next -> index=\(index)")
    }

    func prev() {
        guard index > 0 else { return }
        index -= 1
        DYLog.shared.log("ENGINE prev -> index=\(index)")
    }

    /// 从 hook 回传的 "aweme_ID >> url" 行里提取 url，按 aweme 顺序去重。
    /// 关键：只保留 douyinvod CDN 直链（.mp4，可播），丢弃必失败的 /aweme/v1/play/ 端点（403 no-permission，会黑屏）。
    static func extractOrderedURLs(from videoLines: [String]) -> [URL] {
        var byAweme: [String: URL] = [:]
        var order: [String] = []
        for line in videoLines {
            let parts = line.components(separatedBy: " >> ")
            guard parts.count == 2 else { continue }
            let raw = parts[1].trimmingCharacters(in: .whitespaces)
            // 丢弃 /aweme/v1/play/ 端点（真机实测 403 no-permission，必然黑屏）
            guard !raw.contains("/aweme/v1/play/"), let url = URL(string: raw) else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            if byAweme[key] == nil {
                byAweme[key] = url
                order.append(key)
            }
        }
        return order.compactMap { byAweme[$0] }
    }
}
