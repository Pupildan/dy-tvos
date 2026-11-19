import Foundation
import UIKit

// MARK: - 直播表情包客户端（照反编译 myDV u11.java:1400 /aweme/v1/web/emoji/list + EmojiItem{display_name, emoji_url.url_list}）
// 拉 emoji 列表建 shortcode→图片URL 映射，预下载全部图片，供弹幕内联渲染（[捂脸] → 图片）。
final class DYLiveEmojiClient {
    static let shared = DYLiveEmojiClient()
    private init() {}

    /// shortcode（含方括号，如 "[捂脸]"）→ 图片
    private let imageCache = NSCache<NSString, UIImage>()
    /// 是否已加载过（进程内一次）
    private var loaded = false
    private let queue = DispatchQueue(label: "dy.emoji")

    private let ua = DYLiveClient.liveUA
    private let emojiPath = "/aweme/v1/web/emoji/list"

    /// 加载全部表情图片（进程内一次）。ttwid 由调用方传入（避免跨队列调 DYDanmakuClient.ttwidValue 死锁）。
    /// completion 主队列回调，返回 shortcode→UIImage 映射（含方括号 key）。
    func loadAll(ttwid: String, completion: @escaping ([String: UIImage]) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.loaded {
                DispatchQueue.main.async { completion(self.cachedSnapshot) }
                return
            }
            // 1) emoji list（同款 a_bogus 签名）—— fetchEmojiList 返回非可选 [String:String]
            let list = self.fetchEmojiList(ttwid: ttwid)
            if list.isEmpty {
                DispatchQueue.main.async { completion([:]) }
                return
            }
            // 2) 下载全部表情图片 → NSCache
            var images: [String: UIImage] = [:]
            for (shortcode, urlString) in list {
                guard let url = URL(string: urlString) else { continue }
                if let img = self.downloadSync(url: url, ttwid: ttwid) { images[shortcode] = img }
            }
            self.loaded = true
            self.cachedSnapshot = images
            DispatchQueue.main.async { completion(images) }
        }
    }

    /// 同步查缓存（主队列调，emoji 已 preload）
    func cachedImage(for shortcode: String) -> UIImage? {
        return imageCache.object(forKey: shortcode as NSString)
    }

    private var cachedSnapshot: [String: UIImage] = [:]

    private func fetchEmojiList(ttwid: String) -> [String: String] {
        var out: [String: String] = [:]
        let params = [
            "device_platform": "web", "app_name": "douyin_web", "live_id": "1", "enter_from": "web_live",
            "language": "zh-CN", "tz_name": "Asia/Shanghai", "msToken": DYLiveClient.randomMsToken(),
        ]
        let query = params.map { $0.key + "=" + $0.value }.joined(separator: "&")
        guard let sr = DYSigner.shared.sign(query: query, data: "", path: emojiPath, ua: ua) else { return out }
        let finalQuery = query + "&a_bogus=" + (sr.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sr.value)
        guard let url = URL(string: "https://live.douyin.com\(emojiPath)?" + finalQuery) else { return out }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("https://live.douyin.com/", forHTTPHeaderField: "Referer")
        req.setValue("ttwid=\(ttwid)", forHTTPHeaderField: "Cookie")
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let data, !data.isEmpty,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            let list = (obj["emoji_list"] as? [[String: Any]]) ?? ((obj["data"] as? [String: Any])?["emoji_list"] as? [[String: Any]]) ?? []
            for it in list {
                let dn = (it["display_name"] as? String) ?? ""
                let eu = it["emoji_url"] as? [String: Any] ?? [:]
                let urls = (eu["url_list"] as? [String]) ?? []
                let u = urls.first(where: { $0.hasPrefix("http") }) ?? urls.first ?? ""
                if !dn.isEmpty, !u.isEmpty { out["[\(dn)]"] = u }   // key 带方括号，匹配 content 里的 [捂脸]
            }
        }.resume()
        sem.wait()
        return out
    }

    /// 同步下载一张表情图片（在 emoji client 的串行队列里调，用信号量等完成）
    private func downloadSync(url: URL, ttwid: String) -> UIImage? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        var img: UIImage?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            img = data.flatMap(UIImage.init(data:))
            sem.signal()
        }.resume()
        sem.wait()
        return img
    }
}
