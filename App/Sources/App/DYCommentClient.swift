import Foundation

/// 单条评论（web comment/list JSON 字段映射）。
struct DYCommentItem {
    let cid: String
    let nickname: String
    let avatarUrl: String
    let text: String
    let digg: Int
    let createTimeText: String
}

/// 评论客户端（v147）：GET /aweme/v1/web/comment/list/——web 链（webCommon+web 签名+ttwid），
/// 与 danmaku 同款已验证（探针 status_code=0 total=55091 结构完整）。
/// 分页：cursor 循环（20 条/页），默认取 3 页 60 条；缓存按 awemeId。
/// myDV 未实现评论功能——本端点为抖音 web 标准接口，签名链与已验证的 web 链一致。
final class DYCommentClient {
    static let shared = DYCommentClient()
    private let host = "https://www.douyin.com"
    private let path = "/aweme/v1/web/comment/list/"
    private var cache: [String: [DYCommentItem]] = [:]
    private var inflight = Set<String>()

    /// 取评论（缓存优先）。onDone 主队列回调全部评论（可能为空数组=无评论/失败）。
    func comments(for awemeId: String, pages: Int, onDone: @escaping ([DYCommentItem]) -> Void) {
        guard !awemeId.isEmpty else { onDone([]); return }
        if let hit = cache[awemeId] { onDone(hit); return }
        guard !inflight.contains(awemeId) else { onDone([]); return }
        inflight.insert(awemeId)
        DYDanmakuClient.shared.ensureTTWID { [weak self] in
            guard let self else { return }
            self.fetchPages(awemeId: awemeId, cursor: 0, remaining: max(1, pages), acc: [], seen: []) { [weak self] all in
                guard let self else { return }
                self.inflight.remove(awemeId)
                if !all.isEmpty { self.cache[awemeId] = all }
                DispatchQueue.main.async { onDone(all) }
            }
        }
    }

    private func fetchPages(awemeId: String, cursor: Int, remaining: Int, acc: [DYCommentItem], seen: Set<String>, done: @escaping ([DYCommentItem]) -> Void) {
        guard remaining > 0 else { done(acc); return }
        var p: [(String, String)] = Self.webCommon + [
            ("aweme_id", awemeId),
            ("cursor", String(cursor)),
            ("count", "20"),
            ("item_type", "0"),
            ("version_code", "170400"),
            ("version_name", "17.4.0"),
            ("msToken", Self.randomMsToken()),
            ("screen_width", "2560"),
            ("screen_height", "1440"),
            ("cpu_core_num", "24"),
            ("device_memory", "8"),
        ]
        let ts = String(Int(Date().timeIntervalSince1970))
        p.append(("timestamp", ts))
        let baseQuery = p.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        guard let sr = DYSigner.shared.sign(query: baseQuery, data: "", path: path, ua: DYDanmakuClient.webUA) else {
            DYLog.shared.log("CMT sign fail")
            done(acc); return
        }
        var finalQuery = baseQuery
        if !sr.value.isEmpty { finalQuery += "&a_bogus=\(sr.value)" }
        guard let url = URL(string: "\(host)\(path)?\(finalQuery)") else { done(acc); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue(DYDanmakuClient.webUA, forHTTPHeaderField: "User-Agent")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        let ttwid = DYDanmakuClient.shared.ttwidValue
        if !ttwid.isEmpty { req.setValue("ttwid=\(ttwid)", forHTTPHeaderField: "Cookie") }
        req.setValue("\(host)/video/\(awemeId)", forHTTPHeaderField: "Referer")

        DYLog.shared.log("CMT get id=\(awemeId) cursor=\(cursor)")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let httpStatus = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard err == nil, httpStatus == 200, let data, !data.isEmpty,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  (obj["status_code"] as? Int ?? -1) == 0 else {
                DYLog.shared.log("CMT page cursor=\(cursor) fail http=\(httpStatus)")
                done(acc); return
            }
            let list = obj["comments"] as? [[String: Any]] ?? []
            var acc = acc
            var seen = seen
            for e in list {
                let cid = (e["cid"] as? NSNumber)?.stringValue ?? (e["cid"] as? String ?? "")
                guard !cid.isEmpty, !seen.contains(cid) else { continue }
                guard let text = e["text"] as? String, !text.isEmpty else { continue }
                seen.insert(cid)
                let user = e["user"] as? [String: Any] ?? [:]
                var nick = user["nickname"] as? String ?? ""
                if nick.count > 20 { nick = String(nick.prefix(20)) }
                var avatar = ""
                if let at = user["avatar_thumb"] as? [String: Any], let ul = at["url_list"] as? [String] {
                    avatar = ul.first(where: { $0.hasPrefix("http") }) ?? ""
                }
                let digg = (e["digg_count"] as? NSNumber)?.intValue ?? 0
                var timeText = ""
                if let ct = (e["create_time"] as? NSNumber)?.uint64Value, ct > 0 {
                    let f = DateFormatter()
                    f.dateFormat = "MM月dd日"
                    timeText = f.string(from: Date(timeIntervalSince1970: TimeInterval(ct)))
                }
                acc.append(DYCommentItem(cid: cid, nickname: nick, avatarUrl: avatar, text: text, digg: digg, createTimeText: timeText))
            }
            let hasMore = (obj["has_more"] as? Int ?? 0) == 1
            let nextCursor = (obj["cursor"] as? NSNumber)?.intValue ?? (cursor + 20)
            guard hasMore, !list.isEmpty else { done(acc); return }
            DispatchQueue.main.async {
                self.fetchPages(awemeId: awemeId, cursor: nextCursor, remaining: remaining - 1, acc: acc, seen: seen, done: done)
            }
        }.resume()
    }

    static let webCommon: [(String, String)] = [
        ("device_platform", "webapp"),
        ("aid", "6383"),
        ("channel", "channel_pc_web"),
        ("cookie_enabled", "true"),
        ("browser_language", "zh-CN"),
        ("browser_platform", "Win32"),
        ("browser_name", "Chrome"),
        ("browser_version", "147.0.0.0"),
    ]

    static func randomMsToken() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<126).map { _ in chars.randomElement()! }) + "=="
    }
}
