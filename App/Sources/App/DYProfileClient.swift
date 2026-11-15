import Foundation
import CryptoKit

/// 作者资料（web user/profile/other 响应映射）。
struct DYProfileUser {
    let nickname: String
    let avatarUrl: String
    let secUid: String
    let signature: String
    let followerCount: Int
    let followingCount: Int
    let awemeCount: Int
    let totalFavorited: Int
}

/// 主页/合集身份链（v153，照抄 myDV u11 + 探针实测）：
/// ①UIFID_TEMP：tab/feed 响应 Set-Cookie 下发（160 hex），cookie 罐收走；
/// ②被墙接口需 `uifid` 参数+头 + `x-secsdk-web-signature` 头 = MD5(uifid_timestamp_A96D855A08C0A9707F8BEF0D9A527E4E_全参数k=v&拼接)
///   （u11.i() 原样；签名错误时服务端 403 "Sign Invalid"，正确时过签名关——探针实锤）；
/// ③user/profile/other 匿名全通（探针 sc=0）；aweme/post 探针 200 空响应（Node TLS 指纹疑点），
///   真机 URLSession 重试——成功即解锁作品列表。
final class DYProfileClient {
    static let shared = DYProfileClient()
    private let host = "https://www.douyin.com"
    private let session: URLSession
    /// cookie 罐（myDV sl4 同构：收所有 Set-Cookie；关键键=UIFID_TEMP）
    private var jar: [String: String] = [:]
    private var inflight = false
    private let queue = DispatchQueue(label: "dy.profile")

    /// x-secsdk-web-signature 密钥（myDV u11.i() 硬编码常量，探针实测有效）
    private static let secKey = "A96D855A08C0A9707F8BEF0D9A527E4E"
    static let webUA = DYDanmakuClient.webUA
    private static let webCommon: [(String, String)] = [
        ("device_platform", "webapp"),
        ("aid", "6383"),
        ("channel", "channel_pc_web"),
        ("cookie_enabled", "true"),
        ("browser_language", "zh-CN"),
        ("browser_platform", "Win32"),
        ("browser_name", "Chrome"),
        ("browser_version", "147.0.0.0"),
    ]

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpShouldSetCookies = false
        cfg.httpAdditionalHeaders = ["User-Agent": DYProfileClient.webUA, "Accept-Language": "zh-CN,zh;q=0.9"]
        session = URLSession(configuration: cfg)
    }

    // MARK: - cookie 罐

    /// 吸收响应 Set-Cookie（allHeaderFields 多条 Set-Cookie 会逗号合并；目标 cookie 值均不含逗号，按名定向提取）
    private func absorb(_ resp: URLResponse?) {
        guard let http = resp as? HTTPURLResponse else { return }
        let merged = http.allHeaderFields["Set-Cookie"] as? String ?? ""
        guard !merged.isEmpty else { return }
        queue.async {
            for name in ["UIFID_TEMP", "UIFID", "ttwid", "msToken", "__ac_nonce"] {
                guard let re = try? NSRegularExpression(pattern: name + "=([^;,\\s]+)") else { continue }
                let s = merged as NSString
                if let m = re.firstMatch(in: merged, range: NSRange(location: 0, length: s.length)) {
                    self.jar[name] = s.substring(with: m.range(at: 1))
                }
            }
        }
    }

    private func cookieHeader() -> String {
        var parts: [String] = []
        let ttwid = DYDanmakuClient.shared.ttwidValue
        if !ttwid.isEmpty { parts.append("ttwid=\(ttwid)") }
        for (k, v) in jar { parts.append("\(k)=\(v)") }
        return parts.joined(separator: "; ")
    }

    private func md5hex(_ s: String) -> String {
        Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 对外

    /// 取作者资料 + 试探作品列表。onDone 主队列；nil=失败。
    func profile(for secUid: String, onDone: @escaping (DYProfileUser?, Int) -> Void) {
        guard !secUid.isEmpty else { onDone(nil, 0); return }
        queue.async { [weak self] in
            guard let self else { return }
            self.ensureUIFID { [weak self] in
                guard let self else { return }
                self.fetchProfile(secUid: secUid) { user in
                    // 作品接口真机试探（Node 探针 200 空=TLS 指纹疑点；URLSession 指纹不同，真机日志定论）
                    self.fetchWorks(secUid: secUid) { count in
                        DispatchQueue.main.async { onDone(user, count) }
                    }
                }
            }
        }
    }

    // MARK: - UIFID 种子（tab/feed 响应下发 UIFID_TEMP，探针实锤）

    private func ensureUIFID(_ done: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.jar["UIFID_TEMP"] != nil || self.jar["UIFID"] != nil { done(); return }
            guard !self.inflight else { done(); return }
            self.inflight = true
            let params: [(String, String)] = Self.webCommon + [
                ("aweme_pc_rec_raw_data", "{\"is_client\":false,\"ff_danmaku_status\":1,\"danmaku_switch_status\":1,\"is_dash_user\":1,\"related_recommend\":1,\"is_xigua_user\":0}"),
                ("count", "6"), ("filterGids", ""), ("refresh_index", "1"), ("pull_type", "2"), ("video_type_select", "1"),
                ("msToken", Self.randomMsToken()),
                ("screen_width", "2560"), ("screen_height", "1440"), ("cpu_core_num", "24"), ("device_memory", "8"),
            ]
            let ts = String(Int(Date().timeIntervalSince1970))
            let path = "/aweme/v1/web/tab/feed/"
            let base = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&") + "&timestamp=" + ts
            guard let sr = DYSigner.shared.sign(query: base, data: "", path: path, ua: DYProfileClient.webUA) else {
                DYLog.shared.log("PROFILE seed sign fail"); self.inflight = false; done(); return
            }
            let url = "\(self.host)\(path)?\(base)&a_bogus=\(sr.value)"
            var req = URLRequest(url: URL(string: url)!)
            req.timeoutInterval = 12
            req.setValue(DYProfileClient.webUA, forHTTPHeaderField: "User-Agent")
            req.setValue("https://www.douyin.com/?recommend=1", forHTTPHeaderField: "Referer")
            req.setValue(self.cookieHeader(), forHTTPHeaderField: "Cookie")
            DYLog.shared.log("PROFILE seed tab/feed (取 UIFID_TEMP)")
            self.session.dataTask(with: req) { [weak self] _, resp, err in
                guard let self else { return }
                if let err { DYLog.shared.log("PROFILE seed err: \(err.localizedDescription)") }
                self.absorb(resp)
                self.inflight = false
                DYLog.shared.log("PROFILE seed done uifid=\(self.jar["UIFID_TEMP"] != nil ? "yes" : "no")")
                done()
            }.resume()
        }
    }

    // MARK: - 作者资料（user/profile/other，探针实测匿名 sc=0）

    private func fetchProfile(secUid: String, onDone: @escaping (DYProfileUser?) -> Void) {
        let params: [(String, String)] = Self.webCommon + [
            ("sec_user_id", secUid),
            ("publish_video_strategy_type", "2"),
            ("source", "channel_pc_web"),
            ("version_code", "290100"), ("version_name", "29.1.0"),
            ("msToken", Self.randomMsToken()),
            ("screen_width", "2560"), ("screen_height", "1440"), ("cpu_core_num", "24"), ("device_memory", "8"),
        ]
        self.signedGET("/aweme/v1/web/user/profile/other/", params: params,
                       referer: "https://www.douyin.com/user/" + secUid) { data, resp in
            self.absorb(resp)
            guard let data, !data.isEmpty,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  (obj["status_code"] as? Int ?? -1) == 0,
                  let user = obj["user"] as? [String: Any] else {
                DYLog.shared.event("PROFILE fetch fail http=\((resp as? HTTPURLResponse)?.statusCode ?? -1) len=\(data?.count ?? 0)")
                onDone(nil); return
            }
            var avatar = ""
            if let at = user["avatar_thumb"] as? [String: Any], let ul = at["url_list"] as? [String] {
                avatar = ul.first(where: { $0.hasPrefix("http") }) ?? ""
            }
            let u = DYProfileUser(
                nickname: user["nickname"] as? String ?? "",
                avatarUrl: avatar,
                secUid: user["sec_uid"] as? String ?? secUid,
                signature: user["signature"] as? String ?? "",
                followerCount: (user["follower_count"] as? NSNumber)?.intValue ?? 0,
                followingCount: (user["following_count"] as? NSNumber)?.intValue ?? 0,
                awemeCount: (user["aweme_count"] as? NSNumber)?.intValue ?? 0,
                totalFavorited: (user["total_favorited"] as? NSNumber)?.intValue ?? 0
            )
            DYLog.shared.event("PROFILE ok nick=\(u.nickname) fans=\(u.followerCount) works=\(u.awemeCount)")
            onDone(u)
        }
    }

    // MARK: - 作品列表试探（aweme/post；探针 200 空——真机 URLSession TLS 指纹可能不同）

    private func fetchWorks(secUid: String, onDone: @escaping (Int) -> Void) {
        let params: [(String, String)] = Self.webCommon + [
            ("sec_user_id", secUid), ("count", "10"), ("max_cursor", "0"), ("locate_item_id", ""), ("locate_query", "false"),
            ("show_live_replay_strategy", "1"), ("need_time_list", "1"), ("time_list_query", "0"), ("whale_cut_token", ""),
            ("cut_version", "1"), ("publish_video_strategy_type", "2"), ("from_user_page", "1"),
            ("version_code", "290100"), ("version_name", "29.1.0"),
            ("msToken", Self.randomMsToken()),
            ("screen_width", "2560"), ("screen_height", "1440"), ("cpu_core_num", "24"), ("device_memory", "8"),
        ]
        self.signedGET("/aweme/v1/web/aweme/post/", params: params,
                       referer: "https://www.douyin.com/user/" + secUid) { data, resp in
            self.absorb(resp)
            let http = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard let data, !data.isEmpty,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                DYLog.shared.event("WORKS probe empty http=\(http) len=\(data?.count ?? 0) (TLS 疑点待真机)")
                onDone(-1); return
            }
            let list = (obj["aweme_list"] as? [[String: Any]]) ?? []
            DYLog.shared.event("WORKS probe sc=\(obj["status_code"] as? Int ?? -1) awemes=\(list.count) http=\(http)")
            onDone(list.count)
        }
    }

    // MARK: - 签名 GET（a_bogus → uifid → timestamp → x-secsdk-web-signature，照抄 u11 G0/i()）

    private func signedGET(_ path: String, params: [(String, String)], referer: String,
                           onDone: @escaping (Data?, URLResponse?) -> Void) {
        let ts = String(Int(Date().timeIntervalSince1970))
        let base = params.map { "\($0.0)=\($0.1)" }.joined(separator: "&") + "&timestamp=" + ts
        guard let sr = DYSigner.shared.sign(query: base, data: "", path: path, ua: DYProfileClient.webUA) else {
            DYLog.shared.log("PROFILE sign fail"); onDone(nil, nil); return
        }
        var list = params
        list.append(("a_bogus", sr.value))
        let uifid = jar["UIFID"] ?? jar["UIFID_TEMP"] ?? ""
        if !uifid.isEmpty { list.append(("uifid", uifid)) }
        list.append(("timestamp", ts))
        // x-secsdk-web-signature = MD5(uifid_timestamp_密钥_全参数k=v&拼接)（u11.i() 原样）
        var sig = ""
        if !uifid.isEmpty {
            sig = md5hex(uifid + "_" + ts + "_" + Self.secKey + "_" + list.map { "\($0.0)=\($0.1)" }.joined(separator: "&"))
        }
        let query = list.map { "\($0.0)=\($0.1)" }.joined(separator: "&") + (sig.isEmpty ? "" : "&x-secsdk-web-signature=\(sig)")
        guard let url = URL(string: "\(host)\(path)?\(query)") else { onDone(nil, nil); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue(DYProfileClient.webUA, forHTTPHeaderField: "User-Agent")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue(referer, forHTTPHeaderField: "Referer")
        req.setValue(cookieHeader(), forHTTPHeaderField: "Cookie")
        if !uifid.isEmpty { req.setValue(uifid, forHTTPHeaderField: "uifid") }
        DYLog.shared.log("PROFILE GET \(path) uifid=\(uifid.isEmpty ? 0 : uifid.count)")
        session.dataTask(with: req) { data, resp, err in
            if let err { DYLog.shared.log("PROFILE GET err: \(err.localizedDescription)") }
            onDone(data, resp)
        }.resume()
    }

    static func randomMsToken() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<126).map { _ in chars.randomElement()! }) + "=="
    }
}
