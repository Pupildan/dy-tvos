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

    /// 从 hook 回传的 "aweme_ID >> url" 行里提取 url，按 aweme 顺序去重（每个 aweme 取第一条 douyinvod 优先）。
    static func extractOrderedURLs(from videoLines: [String]) -> [URL] {
        var byAweme: [String: URL] = [:]
        var order: [String] = []
        for line in videoLines {
            // 行格式: "aweme_123 >> https://..."
            let parts = line.components(separatedBy: " >> ")
            guard parts.count == 2, let url = URL(string: parts[1].trimmingCharacters(in: .whitespaces)) else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            if byAweme[key] == nil {
                // 每个 aweme 只取第一次出现的（hook 顺序里 douyinvod .mp4 在前）
                byAweme[key] = url
                order.append(key)
            }
        }
        return order.compactMap { byAweme[$0] }
    }
}
