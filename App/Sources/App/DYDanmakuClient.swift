import Foundation

/// 单条弹幕（DanmakuItem JSON 字段的 Swift 映射，myDV DanmakuItem.java 对应）。
struct DYDanmakuItem {
    let danmakuId: String
    let offsetTime: Double      // ms，视频内位置
    let text: String
}

/// 弹幕数据客户端（照抄 myDV u11.K 弹幕请求 + u11.A ttwid 匿名注册，2026-11-14 反编译原文）：
/// GET https://www.douyin.com/aweme/v1/web/danmaku/get_v2/?<params>
///   app_name=aweme, format=json, group_id=<awemeId>, item_id=<awemeId>,
///   start_time=0, end_time=<durMs>, duration=<durMs>, authentication_token=<token或空>,
///   pc_libra_divert=Windows, support_h265=0, support_dash=1, version_code=170400, version_name=17.4.0
///   + D0() 公共参数(msToken/screen_width/screen_height/cpu_core_num/device_memory) + a_bogus + timestamp
/// 响应 JSON：{status_code, danmaku_list:[{danmaku_id, offset_time, text, ...}]}
/// 需 web 身份：Chrome 桌面 UA(u11.A 原文) + ttwid cookie(ttwid.bytedance.com 匿名注册，无需登录) + Referer https://www.douyin.com/video/<id>。
/// ⚠️ v132 为探针版：authentication_token/group_id 的 proto 字段号未知（aweme-dump 探针同时跑），先传 awemeId/空 token，
///    端点可用性/token 必要性由 DANM 日志实锤后收紧。
final class DYDanmakuClient {
    static let shared = DYDanmakuClient()
    /// web 端 UA（u11.A 原文：ttwid 注册与 web 请求同款 Chrome 147 桌面 UA）
    static let webUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"
    private let host = "https://www.douyin.com"
    private let path = "/aweme/v1/web/danmaku/get_v2/"

    private let session: URLSession
    private var cache: [String: [DYDanmakuItem]] = [:]
    private var inflight = Set<String>()
    private var ttwid: String {
        get { UserDefaults.standard.string(forKey: "dy_ttwid") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "dy_ttwid") }
    }
    private let queue = DispatchQueue(label: "dy.danmaku")

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpShouldSetCookies = false
        cfg.httpAdditionalHeaders = [
            "User-Agent": DYDanmakuClient.webUA,
            "Accept": "*/*",
            "Accept-Language": "zh-CN,zh;q=0.9",
        ]
        session = URLSession(configuration: cfg)
    }

    /// 取 awemeId 的弹幕（缓存优先；inflight 去重；completion 主队列回调，可能为空数组）。
    func items(for awemeId: String, durationMs: Int, completion: @escaping ([DYDanmakuItem]) -> Void) {
        guard !awemeId.isEmpty else { completion([]); return }
        if let hit = cache[awemeId] { completion(hit); return }
        guard !inflight.contains(awemeId) else { completion([]); return }
        inflight.insert(awemeId)
        queue.async { [weak self] in
            guard let self else { return }
            self.ensureTTWID { [weak self] in
                self?.fetch(awemeId: awemeId, durationMs: durationMs) { [weak self] items in
                    guard let self else { return }
                    self.queue.async {
                        self.inflight.remove(awemeId)
                        if !items.isEmpty { self.cache[awemeId] = items }
                        DispatchQueue.main.async { completion(items) }
                    }
                }
            }
        }
    }

    /// 当前 ttwid（web 源播放请求头/设置面板复用；可能为空串）。
    var ttwidValue: String {
        queue.sync { ttwid }
    }

    /// 确保 ttwid 已注册（web 源切换前调用；幂等，完成即回调）。
    func ensureTTWID(_ done: @escaping () -> Void) {
        queue.async { [weak self] in
            self?.ensureTTWID { done() }
        }
    }

    // MARK: - ttwid 匿名注册（照抄 u11.A 原文：POST ttwid.bytedance.com/ttwid/union/register/）

    private func ensureTTWID(_ done: @escaping () -> Void) {
        if !ttwid.isEmpty { done(); return }
        let body = "{\"region\":\"cn\",\"aid\":1768,\"needFid\":false,\"service\":\"www.ixigua.com\",\"migrate_info\":{\"ticket\":\"\",\"source\":\"node\"},\"cbUrlProtocol\":\"https\",\"union\":true}"
        var req = URLRequest(url: URL(string: "https://ttwid.bytedance.com/ttwid/union/register/")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue(DYDanmakuClient.webUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://www.douyin.com", forHTTPHeaderField: "Origin")
        req.setValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")
        req.httpBody = body.data(using: .utf8)
        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            if let err { DYLog.shared.log("DANM ttwid err: \(err.localizedDescription)"); done(); return }
            // ttwid 在 Set-Cookie 里（u11.A：从 headers("Set-Cookie") 提取 ttwid= 值）
            let setCookies = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Set-Cookie") ?? ""
            var found = ""
            for part in setCookies.components(separatedBy: ",") {
                let seg = part.trimmingCharacters(in: .whitespaces)
                if seg.hasPrefix("ttwid=") {
                    let v = seg.dropFirst("ttwid=".count)
                    if let end = v.firstIndex(of: ";") { found = String(v[..<end]) } else { found = String(v) }
                }
            }
            if !found.isEmpty {
                self.ttwid = found
                DYLog.shared.log("DANM ttwid ok len=\(found.count)")
            } else {
                DYLog.shared.log("DANM ttwid MISSING (http=\((resp as? HTTPURLResponse)?.statusCode ?? -1) sc=\(setCookies.prefix(60)))")
            }
            done()
        }.resume()
    }

    // MARK: - 弹幕请求（照抄 u11.K 参数表 + r() web GET 链）

    private func fetch(awemeId: String, durationMs: Int, completion: @escaping ([DYDanmakuItem]) -> Void) {
        let d = max(0, durationMs)
        // web 公共参数（v133 开发机探针实锤：缺这些 douyin web 网关一律 status_code=3 "AppId不合法"）
        let webCommon: [(String, String)] = [
            ("device_platform", "webapp"),
            ("aid", "6383"),
            ("channel", "channel_pc_web"),
            ("cookie_enabled", "true"),
            ("browser_language", "zh-CN"),
            ("browser_platform", "Win32"),
            ("browser_name", "Chrome"),
            ("browser_version", "147.0.0.0"),
        ]
        var p: [(String, String)] = webCommon + [
            ("app_name", "aweme"),
            ("format", "json"),
            ("group_id", awemeId),
            ("item_id", awemeId),
            ("start_time", "0"),
            ("end_time", String(d)),
            ("duration", String(d)),
            // authentication_token 传空即可（v133 探针实锤：mobile proto 无此字段且空值能通）
            ("authentication_token", ""),
            ("pc_libra_divert", "Windows"),
            ("support_h265", "0"),
            ("support_dash", "1"),
            ("version_code", "170400"),
            ("version_name", "17.4.0"),
        ]
        // D0() 公共参数（照抄 DYFeedClient 同款）
        p.append(("msToken", Self.randomMsToken()))
        p.append(("screen_width", "2560"))
        p.append(("screen_height", "1440"))
        p.append(("cpu_core_num", "24"))
        p.append(("device_memory", "8"))
        // 签名输入 = 完整 query 含 timestamp（v133 探针原样：baseQuery+timestamp → sign → a_bogus 后置）
        let ts = String(Int(Date().timeIntervalSince1970))
        let baseQuery = p.map { "\($0.0)=\($0.1)" }.joined(separator: "&") + "&timestamp=\(ts)"
        guard let sr = DYSigner.shared.sign(query: baseQuery, data: "", path: path, ua: DYDanmakuClient.webUA) else {
            DYLog.shared.log("DANM sign fail (not ready)")
            completion([])
            return
        }
        var finalQuery = baseQuery
        if !sr.value.isEmpty { finalQuery += "&a_bogus=\(sr.value)" }
        guard let url = URL(string: "\(host)\(path)?\(finalQuery)") else {
            DYLog.shared.log("DANM url parse fail")
            completion([])
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue(DYDanmakuClient.webUA, forHTTPHeaderField: "User-Agent")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        if !ttwid.isEmpty { req.setValue("ttwid=\(ttwid)", forHTTPHeaderField: "Cookie") }
        req.setValue("\(host)/video/\(awemeId)", forHTTPHeaderField: "Referer")

        DYLog.shared.log("DANM get id=\(awemeId) dur=\(d) bogus_len=\(sr.value.count) ttwid=\(ttwid.isEmpty ? 0 : ttwid.count)")
        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            if let err { DYLog.shared.event("DANM http err: \(err.localizedDescription)"); completion([]); return }
            guard let http = resp as? HTTPURLResponse else { completion([]); return }
            guard let data, !data.isEmpty else {
                DYLog.shared.log("DANM empty body http=\(http.statusCode)")
                completion([])
                return
            }
            guard http.statusCode == 200 else {
                DYLog.shared.event("DANM http=\(http.statusCode) bytes=\(data.count) (端点拒绝?观察 status_code)")
                completion([])
                return
            }
            // JSON 解析（web 端点返回 JSON；DanmakuResponse{status_code, danmaku_list[]}）
            guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                DYLog.shared.log("DANM json parse fail (body=\(String(data: data.prefix(80), encoding: .utf8) ?? "?"))")
                completion([])
                return
            }
            let sc = obj["status_code"] as? Int ?? -1
            guard sc == 0, let list = obj["danmaku_list"] as? [[String: Any]] else {
                DYLog.shared.event("DANM status_code=\(sc) items=0 (0=ok 其他=错误码;若需 token/登录这里会暴露)")
                completion([])
                return
            }
            var items: [DYDanmakuItem] = []
            for e in list {
                guard let text = e["text"] as? String, !text.isEmpty else { continue }
                let off = (e["offset_time"] as? NSNumber)?.doubleValue ?? 0
                let did = (e["danmaku_id"] as? NSNumber)?.stringValue ?? (e["danmaku_id"] as? String ?? "")
                items.append(DYDanmakuItem(danmakuId: did, offsetTime: off, text: text))
            }
            items.sort { $0.offsetTime < $1.offsetTime }
            DYLog.shared.event("DANM ok id=\(awemeId) items=\(items.count) bytes=\(data.count)")
            completion(items)
        }.resume()
    }

    static func randomMsToken() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<126).map { _ in chars.randomElement()! }) + "=="
    }
}
