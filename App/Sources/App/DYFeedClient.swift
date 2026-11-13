import Foundation

/// 原生抖音直连客户端（myDV 移动端方案，照抄 myDV u11.V → sz0 → s13）：
/// GET https://aweme.snssdk.com/aweme/v2/feed/?<params>，现场重签 a_bogus（4 参含 UA）。
/// 响应是 protobuf（s13.f 拒绝 '{' 开头，走 h() 手工 wire-format 解码），不是 JSON。
/// 无限刷：refresh_index 每页 +1，cold_start 首页 "1" 其余 "0"。
/// 无 WebView：正常播放流程零 WebView。
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
        cfg.httpAdditionalHeaders = [
            "User-Agent": DYFeedClient.mobileUA,
            "Accept": "*/*",
            "Accept-Language": "zh-CN,zh;q=0.9",
        ]
        session = URLSession(configuration: cfg)
        ensureDeviceIdentity()
    }

    // MARK: - 启动

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

    /// 拉一页移动端推荐。cookie 可选（有登录态则带，无则靠 device_id 刷）。
    func fetchPage() {
        let coldStart = isFirstPage
        let count = 10

        // 参数严格按 myDV u11.V 顺序
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
        if !consumedIds.isEmpty {
            let joined = consumedIds.joined(separator: ",")
            p.append(("filterGids", joined))
            p.append(("presented_ids", joined))
        }
        p.append(("msToken", msToken()))
        p.append(("screen_width", "2560"))
        p.append(("screen_height", "1440"))
        p.append(("cpu_core_num", "24"))
        p.append(("device_memory", "8"))

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
        req.setValue(DYFeedClient.mobileUA, forHTTPHeaderField: "User-Agent")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue(cookieHeader(), forHTTPHeaderField: "Cookie")

        DYLog.shared.log("FEED mobile GET refresh_index=\(refreshIndex) cold=\(coldStart ? 1 : 0) count=\(count) bogus_len=\(sr.value.count) seen=\(consumedIds.count)")

        let usedIndex = refreshIndex
        refreshIndex += 1
        isFirstPage = false

        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            if let err { DYLog.shared.log("FEED http err: \(err.localizedDescription)"); return }
            guard let http = resp as? HTTPURLResponse else { return }
            guard var data, !data.isEmpty else {
                DYLog.shared.log("FEED empty body (refresh_index=\(usedIndex) http=\(http.statusCode))")
                return
            }
            self.parse(data: data, refreshIndex: usedIndex, http: http)
        }.resume()
    }

    // MARK: - 解析（protobuf 优先，JSON 兜底）

    private func parse(data: Data, refreshIndex: Int, http: HTTPURLResponse?) {
        // 移动端 v2/feed 是 protobuf（s13.f 拒绝 '{'）。若首字节恰好是 '{' 才走 JSON。
        if data.first == 0x7b /* '{' */ {
            if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let list = (obj["aweme_list"] as? [[String: Any]]) ?? (obj["awemes"] as? [[String: Any]]) {
                extractJSON(list: list, root: obj, refreshIndex: refreshIndex)
                return
            }
        }
        // protobuf 路径（照抄 s13.f / e / g 的字段号）
        let bytes = [UInt8](data)
        guard let root = Proto.parse(bytes) else {
            DYLog.shared.log("FEED proto parse fail (refresh_index=\(refreshIndex)) bytes=\(bytes.count) ct=\(http?.value(forHTTPHeaderField: "Content-Type") ?? "?")")
            PlaybackEngine.shared.reportFailure()
            return
        }
        let statusCode = root.varint(1) ?? 0
        if statusCode != 0 {
            let msg = root.string(2) ?? "unknown"
            DYLog.shared.log("FEED proto status_code=\(statusCode) msg=\(msg) (refresh_index=\(refreshIndex))")
            PlaybackEngine.shared.reportFailure()
            return
        }
        let awemeEntries = root.bytesFields(5)
        DYLog.shared.log("FEED proto root fields=\(root.fields.keys.sorted().map(String.init).joined(separator: ",")) awemes=\(awemeEntries.count) (refresh_index=\(refreshIndex))")
        guard !awemeEntries.isEmpty else {
            DYLog.shared.log("FEED proto 0 awemes (refresh_index=\(refreshIndex))")
            PlaybackEngine.shared.reportFailure()
            return
        }
        var ids: [String] = []
        var urls: [URL] = []
        var loggedFirst = false
        var ei = 0
        for entry in awemeEntries {
            DYLog.shared.log("FEED loop a[\(ei)] begin bytes=\(entry.count)")
            guard let aweme = Proto.parse(entry) else { DYLog.shared.log("FEED loop a[\(ei)] parse-nil"); ei += 1; continue }
            DYLog.shared.log("FEED loop a[\(ei)] aweme-ok")
            // video = aweme field 7，退化 field 8（s13.e:229）
            guard let videoBytes = aweme.bytesFields(7).first ?? aweme.bytesFields(8).first,
                  let video = Proto.parse(videoBytes) else { DYLog.shared.log("FEED loop a[\(ei)] video-nil"); ei += 1; continue }
            DYLog.shared.log("FEED loop a[\(ei)] video-ok")
            // 一次性诊断：dump video 消息所有 field（号/wire/长度），定位 bit_rate 真实字段号
            let videoDump = video.fields.keys.sorted().map { k -> String in
                let vals = video.fields[k] ?? []
                let desc = vals.map { v -> String in
                    switch v {
                    case .varint(let n): return "varint=\(n)"
                    case .bytes(let b): return "bytes=\(b.count)"
                    }
                }
                return "f\(k)[\(desc.joined(separator: ","))]"
            }.joined(separator: " ")
            DYLog.shared.log("FEED video-dump a[\(ei)] \(videoDump)")
            // aweme_id = field 1（s13.b 优先 str，退化为 varint）
            guard let id = aweme.string(1) ?? aweme.varint(1).map(String.init), !id.isEmpty else { DYLog.shared.log("FEED loop a[\(ei)] id-nil"); ei += 1; continue }
            DYLog.shared.log("FEED loop a[\(ei)] id=\(id) pick-start")
            // 最高画质：bit_rate 数组（field 21/31）挑最高档；无 bit_rate 则退回默认 play_addr
            var chosen: URL? = pickHighestQuality(from: video, awemeId: id)
            DYLog.shared.log("FEED loop a[\(ei)] pick-done chosen=\(chosen != nil)")
            if chosen == nil {
                // 默认 play_addr：s13.e:229 是 f1(d(7), d(8))。
                // 实测移动端 video field 8 = 直连 douyinvod CDN（720p，快），field 1 = api-play 重定向（540p，慢）。
                // 故优先 field 8，退化 field 1（含 field 9 兜底）。
                var pa: Proto? = nil
                for pb in video.bytesFields(8) + video.bytesFields(1) + video.bytesFields(9) {
                    if let cand = Proto.parse(pb), !Proto.urlList(cand, 0).isEmpty { pa = cand; break }
                }
                if let playAddr = pa {
                    for raw in Proto.urlList(playAddr, 0) {
                        var u = raw
                        if u.hasPrefix("//") { u = "https:" + u }
                        guard u.lowercased().hasPrefix("https://") || u.lowercased().hasPrefix("http://") else { continue }
                        if let url = URL(string: u) { chosen = url; break }
                    }
                }
            }
            DYLog.shared.log("FEED loop a[\(ei)] final chosen=\(chosen != nil)")
            if let url = chosen {
                ids.append(id); urls.append(url)
                if !loggedFirst {
                    loggedFirst = true
                    DYLog.shared.log("FEED first url[\(id)]: \(url.absoluteString.prefix(140))")
                }
            }
            ei += 1
        }
        consumedIds.append(contentsOf: ids)
        DYLog.shared.log("FEED mobile page refresh_index=\(refreshIndex): awemes=\(awemeEntries.count) usable=\(ids.count) total_seen=\(consumedIds.count)")
        guard !ids.isEmpty else {
            DYLog.shared.log("FEED proto parsed 0 usable videos (refresh_index=\(refreshIndex)) — 检查 video/play_addr 字段号")
            PlaybackEngine.shared.reportFailure()
            return
        }
        PlaybackEngine.shared.merge(ids: ids, urls: urls,
                                    replaceExisting: false,
                                    autoPlay: PlaybackEngine.shared.urls.isEmpty,
                                    refresh: false)
    }

    private func extractJSON(list: [[String: Any]], root: [String: Any], refreshIndex: Int) {
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
                if u.contains("/aweme/v1/play/") { continue }
                if let url = URL(string: u) { ids.append(id); urls.append(url); break }
            }
        }
        consumedIds.append(contentsOf: ids)
        DYLog.shared.log("FEED json page refresh_index=\(refreshIndex): awemes=\(list.count) usable=\(ids.count)")
        guard !ids.isEmpty else { return }
        PlaybackEngine.shared.merge(ids: ids, urls: urls,
                                    replaceExisting: false,
                                    autoPlay: PlaybackEngine.shared.urls.isEmpty,
                                    refresh: false)
    }

    /// 播放失败/过期重拉当前页。
    func refetchCurrent() {
        refreshIndex = max(1, refreshIndex - 1)
        fetchPage()
    }

    // MARK: - 最高画质（照抄 s13.e BitRate 解析 + DataModelKt.highestQualityBitRate 排序）

    /// 从 video 子消息挑最高清直链。
    /// bit_rate 数组 = video field 21（退化 31）；每档：field 1=gearName、2=width、3=height、
    /// 4=playAddr(内含 url_list)、5(退化 7)=bitRateValue。
    /// 排序（highestQualityBitRate，取最大）：分辨率 h*w → fps → bitRateValue → gearName!=adapt_lowest。
    /// 无 bit_rate 档则退回默认 play_addr（field 1/9）。
    func pickHighestQuality(from video: Proto, awemeId: String) -> URL? {
        var entries: [[UInt8]] = video.bytesFields(21)
        if entries.isEmpty { entries = video.bytesFields(31) }

        struct Variant { let url: URL; let w: Int; let h: Int; let fps: Int; let bitrate: Int; let gear: String }
        var variants: [Variant] = []
        var dumped = false
        for e in entries {
            guard let br = Proto.parse(e) else { continue }
            // 一次性诊断：dump bit_rate 首条的所有 field（号/wire/长度），确认真实结构（is_h265/play_addr 字段号）
            if !dumped {
                dumped = true
                let dump = br.fields.keys.sorted().map { k -> String in
                    let vals = br.fields[k] ?? []
                    let sizes = vals.map { v -> String in
                        switch v {
                        case .varint(let n): return "varint=\(n)"
                        case .bytes(let b): return "bytes=\(b.count)"
                        }
                    }
                    return "f\(k)[\(sizes.joined(separator: ","))]"
                }.joined(separator: " ")
                DYLog.shared.log("FEED bitrate-dump aweme=\(awemeId) entries=\(entries.count) \(dump)")
            }
            let gear = br.string(1) ?? ""
            let w = Int(br.varint(2) ?? 0)
            let h = Int(br.varint(3) ?? 0)
            // playAddr = field 4，取其 url_list
            guard let paBytes = br.bytesFields(4).first, let pa = Proto.parse(paBytes) else { continue }
            let urls = Proto.urlList(pa, 0)
            guard let raw = urls.first(where: { $0.lowercased().hasPrefix("https://") || $0.lowercased().hasPrefix("http://") }),
                  let url = URL(string: raw) else { continue }
            // bitRateValue = field 5，退化 7
            let bitrate = Int(br.varint(5) ?? br.varint(7) ?? 0)
            variants.append(Variant(url: url, w: w, h: h, fps: 0, bitrate: bitrate, gear: gear))
        }
        guard !variants.isEmpty else { return nil }

        // highestQualityBitRate：分辨率 h*w → fps → bitRateValue → gearName!=adapt_lowest，取最大
        let best = variants.max { a, b in
            let resA = a.h * a.w, resB = b.h * b.w
            if resA != resB { return resA < resB }
            if a.fps != b.fps { return a.fps < b.fps }
            if a.bitrate != b.bitrate { return a.bitrate < b.bitrate }
            let lowA = a.gear == "adapt_lowest" ? 0 : 1
            let lowB = b.gear == "adapt_lowest" ? 0 : 1
            return lowA < lowB
        }
        if let b = best {
            DYLog.shared.log("FEED quality pick \(b.w)x\(b.h) bitrate=\(b.bitrate) gear=\(b.gear) of \(variants.count) variants")
        }
        return best?.url
    }

    func cookieHeaderForPlayback() -> String? {
        let cookies = HTTPCookieStorage.shared.cookies ?? []
        let douyin = cookies.filter { $0.domain.contains("douyin") || $0.domain.contains("snssdk") }
        let header = douyin.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        return header.isEmpty ? nil : header
    }

    private func cookieHeader() -> String? { cookieHeaderForPlayback() }

    // MARK: - 会话/设备

    private func recRawData(coldStart: Bool) -> String {
        if coldStart {
            return "{\"is_client\":false,\"ff_danmaku_status\":1,\"danmaku_switch_status\":1,\"is_dash_user\":1,\"related_recommend\":1,\"is_xigua_user\":0,\"live_insert_type\":0,\"insert_ads\":0}"
        }
        let recent = consumedIds.suffix(20).joined(separator: ",")
        return "{\"videoPrefer\":{\"fsn\":[],\"like\":[\(recent)],\"halfMin\":[\(recent)],\"min\":[\(recent)],\"collected\":[],\"skip\":[],\"complete_play\":[]},\"is_client\":false,\"ff_danmaku_status\":1,\"danmaku_switch_status\":1,\"is_dash_user\":1,\"related_recommend\":1,\"is_xigua_user\":0,\"live_insert_type\":0,\"insert_ads\":0}"
    }

    private func ensureDeviceIdentity() {
        let d = UserDefaults.standard
        if d.string(forKey: "dy_device_id") == nil { d.set(randomDigits(19), forKey: "dy_device_id") }
        if d.string(forKey: "dy_install_id") == nil { d.set(randomDigits(19), forKey: "dy_install_id") }
    }

    private var deviceID: String { UserDefaults.standard.string(forKey: "dy_device_id") ?? "0" }
    private var installID: String { UserDefaults.standard.string(forKey: "dy_install_id") ?? "0" }

    private func msToken() -> String {
        for c in HTTPCookieStorage.shared.cookies ?? [] where c.name == "msToken" { return c.value }
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<126).map { _ in chars.randomElement()! }) + "=="
    }

    private func randomDigits(_ n: Int) -> String {
        String((0..<n).map { _ in "0123456789".randomElement()! })
    }
}

/// 最小 protobuf wire-format 解码器（照抄 myDV s13.h 的字段收集思路）。
/// 只支持解析需要的字段：varint 与 length-delimited。字段号 → 多个值（repeated 支持）。
struct Proto {
    enum Value {
        case varint(UInt64)
        case bytes([UInt8])
    }
    let fields: [Int: [Value]]

    static func parse(_ data: [UInt8]) -> Proto? {
        return parse(data, depth: 0)
    }
    /// v90：加 depth 上限，防深嵌套 protobuf 递归 parse 栈溢出。
    private static func parse(_ data: [UInt8], depth: Int) -> Proto? {
        guard depth < 16 else { return nil }
        var map: [Int: [Value]] = [:]
        var i = 0
        func readVarint(_ i: inout Int) -> UInt64? {
            var shift: UInt64 = 0
            var result: UInt64 = 0
            while i < data.count {
                let b = data[i]; i += 1
                result |= UInt64(b & 0x7f) << shift
                if b & 0x80 == 0 { return result }
                shift += 7
                if shift > 63 { return nil }
            }
            return nil
        }
        while i < data.count {
            guard let key = readVarint(&i) else { return nil }
            let fieldNum = Int(key >> 3)
            let wire = Int(key & 0x07)
            guard fieldNum != 0 else { return nil }
            switch wire {
            case 0:
                guard let v = readVarint(&i) else { return nil }
                map[fieldNum, default: []].append(.varint(v))
            case 2:
                guard let len = readVarint(&i) else { return nil }
                let l = Int(len)
                guard l >= 0, i + l <= data.count else { return nil }
                let slice = Array(data[i..<(i + l)])
                i += l
                map[fieldNum, default: []].append(.bytes(slice))
            case 1: i += 8
            case 5: i += 4
            default:
                return nil
            }
        }
        return Proto(fields: map)
    }

    private func firstField(_ n: Int) -> Value? { fields[n]?.first }

    func varint(_ n: Int) -> UInt64? {
        if case .varint(let v)? = firstField(n) { return v }
        return nil
    }
    func bytesFields(_ n: Int) -> [[UInt8]] {
        (fields[n] ?? []).compactMap { if case .bytes(let b) = $0 { return b } else { return nil } }
    }
    func strings(_ n: Int) -> [String] {
        bytesFields(n).compactMap { String(data: Data($0), encoding: .utf8) }
    }
    func string(_ n: Int) -> String? { strings(n).first }

    /// 是否 http(s) 开头（s13.d）。
    private static func isHttp(_ s: String) -> Bool {
        s.hasPrefix("http://") || s.hasPrefix("https://")
    }

    /// 提取 PlayAddr.urlList，严格照抄 s13.a 的字段优先级：
    /// field 2 →（depth<2 时）递归子消息 → field 1。每步只收 http(s) 开头的串（s13.d）。
    /// field 1 装的是 uri（如 v0300fg…），真正可播的 http CDN URL 在 field 2。
    /// v90：递归加预算上限（防移动端 protobuf 深嵌套/多 bytes 字段导致栈溢出或内存爆掉）。
    static func urlList(_ msg: Proto, _ depth: Int) -> [String] {
        return urlList(msg, depth, budget: 64)
    }
    private static func urlList(_ msg: Proto, _ depth: Int, budget: Int) -> [String] {
        guard budget > 0 else { return [] }   // 预算耗尽，停止递归
        // 1) field 2
        let f2 = msg.strings(2).filter(isHttp)
        if !f2.isEmpty { return f2 }
        // 2) 递归子消息（所有 bytes 字段尝试解析，按字段号序）—— depth<2 且预算递减
        if depth < 2 {
            var rec: [String] = []
            var remaining = budget
            for key in msg.fields.keys.sorted() {
                for case .bytes(let b) in (msg.fields[key] ?? []) {
                    guard remaining > 0 else { return rec }
                    remaining -= 1
                    if let nested = parse(b) {
                        rec.append(contentsOf: urlList(nested, depth + 1, budget: remaining))
                    }
                }
            }
            if !rec.isEmpty { return rec }
        }
        // 3) field 1
        return msg.strings(1).filter(isHttp)
    }
}
