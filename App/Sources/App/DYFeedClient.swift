import Foundation

/// 原生抖音直连客户端（myDV 移动端方案，照抄 myDV u11.V → sz0）：
/// GET https://aweme.snssdk.com/aweme/v2/feed/?<params>，现场重签 a_bogus（4 参含 UA）。
/// 无限刷：refresh_index 每页 +1，cold_start 首页 "1" 其余 "0"（蓝图 §1）。
/// 无 WebView：正常播放流程零 WebView；参数直接构造，不回放模板。
final class DYFeedClient {
    static let shared = DYFeedClient()

    /// 移动端接口（myDV sz0:63 aweme.snssdk.com + /aweme/v2/feed/）
    private let baseHost = "https://aweme.snssdk.com"
    private let feedPath = "/aweme/v2/feed/"
    /// 移动端 UA（myDV u11.p0():440）——签名第 4 参 + 请求头必须一致
    static let mobileUA = "com.ss.android.ugc.aweme/391000 (Linux; U; Android 16; zh_CN; Pixel 10 Pro)"

    private let session: URLSession
    private var signerReady = false
    private var booted = false

    /// 分页游标：refresh_index 每页递增（首页 1）
    private var refreshIndex = 1
    /// 首批 cold_start=1，之后 0
    private var isFirstPage = true
    /// 已消费 aweme id（去重 + rec_raw_data 的 like/min）
    private var consumedIds: [String] = []

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpShouldSetCookies = true
        // 移动端请求头（myDV sz0:65）——仅 UA/Accept/Accept-Language，无 Referer/sec-fetch-*
        cfg.httpAdditionalHeaders = [
            "User-Agent": DYFeedClient.mobileUA,
            "Accept": "*/*",
            "Accept-Language": "zh-CN,zh;q=0.9",
        ]
        session = URLSession(configuration: cfg)
        // 稳定设备标识：首次生成后固化（蓝图 §10 风控要求）
        ensureDeviceIdentity()
    }

    // MARK: - 启动

    /// 启动：等签名器就绪 → 原生拉第一批（不再依赖 WebView 泵捕获模板）
    func start() {
        DYSigner.shared.onReady = { [weak self] in
            self?.signerReady = true
            self?.tryStart()
        }
        DYSigner.shared.initialize()
    }

    private func tryStart() {
        guard signerReady, !booted else { return }
        booted = true
        DYLog.shared.log("FEED native mobile pipeline armed (aweme.snssdk.com/v2/feed)")
        fetchPage()
    }

    // MARK: - 翻页

    /// 拉一页移动端推荐。首页 cold_start=1；之后 refresh_index 递增、cold_start=0。
    /// cookie 可选：移动端接口靠 device_id 而非 sessionid 即可刷（myDV 无需登录），
    /// 有登录 cookie 则带上提升推荐质量，没有照样请求。
    func fetchPage() {
        let coldStart = isFirstPage
        let count = 10

        // 参数严格按 myDV u11.V(2177-2246) 顺序；D0 追加公共参数（msToken/屏幕/指纹）
        var p: [(String, String)] = [
            ("device_platform", "android"),
            ("aid", "1128"),
            ("channel", "douyin"),
            ("version_code", "391000"),
            ("version_name", "39.10.0"),
            ("os_version", "16"),
            ("os_api", "34"),
            ("language", "zh"),
            ("count", String(count)),
            ("refresh_index", String(refreshIndex)),
            ("device_id", deviceID),
            ("install_id", installID),
            ("cookie_enabled", "true"),
            ("downlink", "10"),
            ("cold_start", coldStart ? "1" : "0"),
            ("refer", "1"),
            ("pull_type", coldStart ? "2" : "0"),
            ("aweme_rec_raw_data", recRawData(coldStart: coldStart)),
        ]
        // seen ids → filterGids/presented_ids（仅非空时带，蓝图 §1）
        if !consumedIds.isEmpty {
            let joined = consumedIds.joined(separator: ",")
            p.append(("filterGids", joined))
            p.append(("presented_ids", joined))
        }
        // D0 公共参数（蓝图 §6）
        p.append(("msToken", msToken()))
        p.append(("screen_width", "2560"))
        p.append(("screen_height", "1440"))
        p.append(("cpu_core_num", "24"))
        p.append(("device_memory", "8"))

        // 拼 query（k=v&k=v，不含 a_bogus）→ 现场重签（4 参含移动端 UA）
        let query = p.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        guard let sr = DYSigner.shared.sign(query: query, data: "", path: feedPath, ua: DYFeedClient.mobileUA) else {
            DYLog.shared.log("FEED sign fail (refresh_index=\(refreshIndex))")
            PlaybackEngine.shared.reportFailure()
            return
        }
        var finalQuery = query
        if !sr.value.isEmpty { finalQuery += "&a_bogus=\(sr.value)" }
        guard let url = URL(string: "\(baseHost)\(feedPath)?\(finalQuery)") else {
            DYLog.shared.log("FEED URL parse fail")
            return
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        // 移动端请求头（sz0:65）——UA 与签名第 4 参一致
        req.setValue(DYFeedClient.mobileUA, forHTTPHeaderField: "User-Agent")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        // cookie 可选：有登录态就带（提升推荐质量），没有则不带头（移动端靠 device_id 即可刷）
        req.setValue(cookieHeader(), forHTTPHeaderField: "Cookie")

        DYLog.shared.log("FEED mobile GET refresh_index=\(refreshIndex) cold=\(coldStart ? 1 : 0) count=\(count) bogus_len=\(sr.value.count) seen=\(consumedIds.count)")

        // 推进游标：本次请求已用掉当前 refresh_index，下一页用下一个
        let usedIndex = refreshIndex
        refreshIndex += 1
        isFirstPage = false

        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            if let err { DYLog.shared.log("FEED http err: \(err.localizedDescription)"); return }
            guard let http = resp as? HTTPURLResponse else { return }
            guard let data, !data.isEmpty else {
                DYLog.shared.log("FEED empty body (refresh_index=\(usedIndex) http=\(http.statusCode))")
                return
            }
            self.parse(data: data, refreshIndex: usedIndex)
        }.resume()
    }

    /// 解析 feed JSON → aweme_id + 直链 → 引擎统一合并（读 has_more 供续刷判断，蓝图 §9）
    private func parse(data: Data, refreshIndex: Int) {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = (obj["aweme_list"] as? [[String: Any]]) ?? (obj["awemes"] as? [[String: Any]]) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary \(data.count)B>"
            DYLog.shared.log("FEED parse fail (refresh_index=\(refreshIndex)) body=\(String(body.prefix(200)))")
            PlaybackEngine.shared.reportFailure()
            return
        }
        let hasMore = (obj["has_more"] as? Int) ?? 0
        var ids: [String] = []
        var urls: [URL] = []
        for a in list {
            guard let id = a["aweme_id"] as? String else { continue }
            let video = a["video"] as? [String: Any] ?? [:]
            let pa = (video["play_addr"] as? [String: Any]) ?? (video["download_addr"] as? [String: Any]) ?? [:]
            guard let ul = pa["url_list"] as? [String] else { continue }
            for raw in ul {
                var u = raw
                if u.hasPrefix("//") { u = "https:" + u }
                if u.contains("/aweme/v1/play/") { continue } // 403 坏端点
                if let url = URL(string: u) { ids.append(id); urls.append(url); break }
            }
        }
        consumedIds.append(contentsOf: ids)
        DYLog.shared.log("FEED mobile page refresh_index=\(refreshIndex): awemes=\(list.count) usable=\(ids.count) has_more=\(hasMore) total_seen=\(consumedIds.count)")
        guard !ids.isEmpty else { return }
        PlaybackEngine.shared.merge(ids: ids, urls: urls,
                                    replaceExisting: false,
                                    autoPlay: PlaybackEngine.shared.urls.isEmpty,
                                    refresh: false)
    }

    /// 播放失败/过期重拉当前页（引擎回调）——同页重签重拉。
    func refetchCurrent() {
        // 回退一页游标，重签重拉当前 refresh_index
        refreshIndex = max(1, refreshIndex - 1)
        fetchPage()
    }

    // MARK: - 会话/设备（蓝图 §10）

    /// aweme_rec_raw_data（myDV u11:2171-2174）
    private func recRawData(coldStart: Bool) -> String {
        if coldStart {
            return "{\"is_client\":false,\"ff_danmaku_status\":1,\"danmaku_switch_status\":1,\"is_dash_user\":1,\"related_recommend\":1,\"is_xigua_user\":0,\"live_insert_type\":0,\"insert_ads\":0}"
        }
        let recent = consumedIds.suffix(20).joined(separator: ",")
        return "{\"videoPrefer\":{\"fsn\":[],\"like\":[\(recent)],\"halfMin\":[\(recent)],\"min\":[\(recent)],\"collected\":[],\"skip\":[],\"complete_play\":[]},\"is_client\":false,\"ff_danmaku_status\":1,\"danmaku_switch_status\":1,\"is_dash_user\":1,\"related_recommend\":1,\"is_xigua_user\":0,\"live_insert_type\":0,\"insert_ads\":0}"
    }

    /// 稳定 device_id/install_id：首次随机生成后存 UserDefaults（风控要求不变）
    private func ensureDeviceIdentity() {
        let d = UserDefaults.standard
        if d.string(forKey: "dy_device_id") == nil {
            d.set(randomDigits(19), forKey: "dy_device_id")
        }
        if d.string(forKey: "dy_install_id") == nil {
            d.set(randomDigits(19), forKey: "dy_install_id")
        }
    }

    private var deviceID: String { UserDefaults.standard.string(forKey: "dy_device_id") ?? "0" }
    private var installID: String { UserDefaults.standard.string(forKey: "dy_install_id") ?? "0" }

    /// msToken：优先取共享 cookie 罐里的 msToken，否则随机兜底（蓝图 §7 D()）
    private func msToken() -> String {
        for c in HTTPCookieStorage.shared.cookies ?? [] where c.name == "msToken" {
            return c.value
        }
        // D() 兜底：126 位 [A-Za-z0-9] + "=="
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        let body = String((0..<126).map { _ in chars.randomElement()! })
        return body + "=="
    }

    /// 共享 cookie 罐 → "k=v; k=v"（扫码登录写入的 sessionid/ttwid/msToken 等）。
    /// 供两处使用：feed 请求头 + 播放器 CDN 直链请求头。internal 以便 NativePlayerView 复用。
    func cookieHeaderForPlayback() -> String? {
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        let douyin = cookies.filter { $0.domain.contains("douyin") || $0.domain.contains("snssdk") }
        let header = douyin.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        return header.isEmpty ? nil : header
    }

    /// feed 请求用的 cookie 头（同上，语义别名，保持调用点可读）。
    private func cookieHeader() -> String? {
        cookieHeaderForPlayback()
    }

    private func randomDigits(_ n: Int) -> String {
        String((0..<n).map { _ in "0123456789".randomElement()! })
    }
}
