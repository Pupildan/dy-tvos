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

    // MARK: - 视频源（v135 设置面板切换：mobile=移动端推荐；web=抖音精选/PC端）

    /// 当前视频源（源切换时重置分页状态 + 引擎清空 + 立即拉新源首页）
    private(set) var source: DYFeedSource = .mobile
    /// web 源分页游标（refresh_index 递增，b0 配方）
    private var webRefreshIndex = 1

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

    /// 拉一页当前源的推荐（移动端=protobuf；web=抖音精选 JSON）。
    func fetchPage() {
        switch source {
        case .mobile: fetchMobilePage()
        case .web: fetchWebPage()
        }
    }

    /// 源切换（设置面板）：重置分页 + 引擎清空 + 立即拉新源首页。
    func setSource(_ s: DYFeedSource) {
        guard s != source else { return }
        DYLog.shared.event("FEED source switch \(source) -> \(s)")
        source = s
        refreshIndex = 1
        isFirstPage = true
        consumedIds = []
        webRefreshIndex = 1
        PlaybackEngine.shared.source = s
        PlaybackEngine.shared.reset()
        fetchPage()
    }

    /// 拉一页移动端推荐。cookie 可选（有登录态则带，无则靠 device_id 刷）。
    private func fetchMobilePage() {
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

        DYLog.shared.count("feed_page")
        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            if let err { DYLog.shared.event("FEED http err: \(err.localizedDescription)"); DYLog.shared.count("feed_http_err"); return }
            guard let http = resp as? HTTPURLResponse else { return }
            guard var data, !data.isEmpty else {
                DYLog.shared.log("FEED empty body (refresh_index=\(usedIndex) http=\(http.statusCode))")
                return
            }
            self.parse(data: data, refreshIndex: usedIndex, http: http)
        }.resume()
    }

    /// 拉一页抖音精选（web tab/feed）。b0 配方照抄 u11.java:2701（参数原样）+
    /// webCommon（v133 danmaku 探针实锤：www.douyin.com web API 缺 aid=6383 等一律"AppId不合法"）+
    /// web 签名 getABogus(webUA) + ttwid cookie（u11.A 匿名注册）。
    /// 开发机探针已验证：status_code=0、分页正常、play_addr.url_list 含 douyinvod 直链。
    private func fetchWebPage() {
        let usedIndex = webRefreshIndex
        let pullType = usedIndex == 1 ? 1 : 0
        let gids = consumedIds.suffix(10).joined(separator: ",")
        let cold = isFirstPage
        let raw = cold
            ? "{\"is_client\":false,\"ff_danmaku_status\":1,\"danmaku_switch_status\":0,\"is_dash_user\":1,\"related_recommend\":1,\"is_xigua_user\":0}"
            : "{\"videoPrefer\":{\"fsn\":[],\"like\":[],\"halfMin\":[\(gids)],\"min\":[\(gids)]},\"seo_info\":\"\",\"is_client\":false,\"ff_danmaku_status\":1,\"danmaku_switch_status\":1,\"is_dash_user\":1,\"is_auto_play\":0,\"is_full_screen\":0,\"is_full_webscreen\":0,\"is_mute\":0,\"is_speed\":1,\"is_visible\":1,\"related_recommend\":1,\"is_xigua_user\":0}"
        var p: [(String, String)] = [
            ("device_platform", "webapp"),
            ("aid", "6383"),
            ("channel", "channel_pc_web"),
            ("cookie_enabled", "true"),
            ("browser_language", "zh-CN"),
            ("browser_platform", "Win32"),
            ("browser_name", "Chrome"),
            ("browser_version", "147.0.0.0"),
            ("filterGids", gids),
            ("tag_id", ""),
            ("share_aweme_id", ""),
            ("live_insert_type", ""),
            ("count", "10"),
            ("refresh_index", String(usedIndex)),
            ("video_type_select", "1"),
            ("aweme_pc_rec_raw_data", raw),
            ("pull_type", String(pullType)),
            ("min_window", "0"),
            ("free_right", "0"),
            ("view_count", "0"),
            ("plug_block", "0"),
            ("ug_source", ""),
            ("creative_id", ""),
            ("pc_libra_divert", "Windows"),
            ("support_h265", "1"),
            ("support_dash", "1"),
            ("webcast_sdk_version", "170400"),
            ("webcast_version_code", "170400"),
            ("screen_width", "2560"),
            ("screen_height", "1440"),
            ("cpu_core_num", "24"),
            ("device_memory", "8"),
            ("timestamp", String(Int(Date().timeIntervalSince1970))),
            ("msToken", msToken()),
        ]
        let query = p.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        guard let sr = DYSigner.shared.sign(query: query, data: "", path: "/aweme/v1/web/tab/feed/", ua: DYDanmakuClient.webUA) else {
            DYLog.shared.log("FEED web sign fail (refresh_index=\(usedIndex))")
            PlaybackEngine.shared.reportFailure()
            return
        }
        var finalQuery = query
        if !sr.value.isEmpty { finalQuery += "&a_bogus=\(sr.value)" }
        guard let url = URL(string: "https://www.douyin.com/aweme/v1/web/tab/feed/?\(finalQuery)") else {
            DYLog.shared.log("FEED web URL parse fail")
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue(DYDanmakuClient.webUA, forHTTPHeaderField: "User-Agent")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue("https://www.douyin.com/", forHTTPHeaderField: "Referer")
        let ttwid = DYDanmakuClient.shared.ttwidValue
        if !ttwid.isEmpty { req.setValue("ttwid=\(ttwid)", forHTTPHeaderField: "Cookie") }

        webRefreshIndex += 1
        isFirstPage = false
        DYLog.shared.log("FEED web GET refresh_index=\(usedIndex) cold=\(cold ? 1 : 0) bogus_len=\(sr.value.count) ttwid=\(ttwid.isEmpty ? 0 : ttwid.count)")

        DYLog.shared.count("feed_page")
        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            if let err { DYLog.shared.event("FEED web http err: \(err.localizedDescription)"); DYLog.shared.count("feed_http_err"); return }
            guard let http = resp as? HTTPURLResponse else { return }
            guard let data, !data.isEmpty else {
                DYLog.shared.log("FEED web empty body (refresh_index=\(usedIndex) http=\(http.statusCode))")
                return
            }
            self.parseWeb(data: data, refreshIndex: usedIndex, http: http)
        }.resume()
    }

    /// 解析 web tab/feed JSON（{status_code, aweme_list:[{aweme_id, desc, video:{play_addr, play_addr_265, download_addr, duration, bit_rate}, images, ...}], has_more}）。
    /// 过滤：图集(images 非空)、无 play_addr 直链的条目。播放链复用 selectBestPlayUrl 四级优先级（web url_list 同样适配）。
    private func parseWeb(data: Data, refreshIndex: Int, http: HTTPURLResponse) {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            DYLog.shared.log("FEED web json parse fail (refresh_index=\(refreshIndex) bytes=\(data.count))")
            PlaybackEngine.shared.reportFailure()
            return
        }
        let statusCode = obj["status_code"] as? Int ?? -1
        guard statusCode == 0 else {
            DYLog.shared.event("FEED web status_code=\(statusCode) msg=\(obj["status_msg"] as? String ?? "?")")
            PlaybackEngine.shared.reportFailure()
            return
        }
        let list = obj["aweme_list"] as? [[String: Any]] ?? []
        var ids: [String] = []
        var urls: [URL] = []
        var durations: [Int] = []
        var filtered = 0
        for a in list {
            guard let id = a["aweme_id"] as? String, !id.isEmpty else { DYLog.shared.count("web_parse_id_nil"); continue }
            if let imgs = a["images"] as? [[String: Any]], !imgs.isEmpty {
                DYLog.shared.count("filter_type")
                filtered += 1
                continue   // 图集帖
            }
            guard let video = a["video"] as? [String: Any] else { DYLog.shared.count("web_parse_video_nil"); filtered += 1; continue }
            var candidates: [String] = []
            if let pa = video["play_addr"] as? [String: Any], let ul = pa["url_list"] as? [String] { candidates = ul }
            if candidates.isEmpty, let p265 = video["play_addr_265"] as? [String: Any], let ul = p265["url_list"] as? [String] { candidates = ul }
            if candidates.isEmpty, let da = video["download_addr"] as? [String: Any], let ul = da["url_list"] as? [String] { candidates = ul }   // 兜底（水印版）
            let normalized = candidates.filter { $0.lowercased().hasPrefix("https://") || $0.lowercased().hasPrefix("http://") }
            guard let raw = Self.selectBestPlayUrl(normalized), let url = URL(string: raw) else {
                DYLog.shared.count("parse_no_url")
                filtered += 1
                continue
            }
            let dur = (video["duration"] as? NSNumber)?.intValue ?? 0
            guard dur > 0 else { DYLog.shared.count("filter_nodur"); filtered += 1; continue }
            ids.append(id); urls.append(url); durations.append(dur)
        }
        DYLog.shared.count("feed_aweme", by: list.count)
        DYLog.shared.count("feed_usable", by: ids.count)
        consumedIds.append(contentsOf: ids)
        DYLog.shared.log("FEED web page refresh_index=\(refreshIndex): awemes=\(list.count) usable=\(ids.count) filtered=\(filtered) total_seen=\(consumedIds.count)")
        guard !ids.isEmpty else {
            DYLog.shared.event("FEED web page refresh_index=\(refreshIndex): 0 usable videos")
            PlaybackEngine.shared.reportFailure()
            return
        }
        PlaybackEngine.shared.merge(ids: ids, urls: urls,
                                    replaceExisting: false,
                                    autoPlay: PlaybackEngine.shared.urls.isEmpty,
                                    refresh: false,
                                    allDurations: durations)
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
        var rawVideos: [[UInt8]] = []
        var redirects: [URL?] = []
        var durations: [Int] = []
        var loggedFirst = false
        var filtered = 0
        var ei = 0
        for entry in awemeEntries {
            guard let aweme = Proto.parse(entry) else { DYLog.shared.count("parse_aweme_nil"); ei += 1; continue }
            // video = aweme field 7，退化 field 8（s13.e:229）
            guard let videoBytes = aweme.bytesFields(7).first ?? aweme.bytesFields(8).first,
                  let video = Proto.parse(videoBytes) else { DYLog.shared.count("parse_video_nil"); ei += 1; continue }
            // 每页首条 dump video 全字段（号/wire/长度）——监控 schema 漂移。
            // 已实锤：field 21 = 单 varint 时间戳（URL 生成时刻，epoch 解码≈抓取时刻），非 bit_rate 子消息。
            if ei == 0 {
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
                DYLog.shared.log("FEED video-dump a[0] \(videoDump)")
            }
            // aweme_id = field 1（s13.b 优先 str，退化为 varint）
            guard let id = aweme.string(1) ?? aweme.varint(1).map(String.init), !id.isEmpty else { DYLog.shared.count("parse_id_nil"); ei += 1; continue }
            // 无感过滤（v129，照 myDV filterPrimaryPlayableAwemes 语义 type==0 才进池）：
            // ① awemeType != 0（图集/特殊帖；照 s13.e:371 探字段 43/55/61）
            // ② dur=0（wire 实锤：v128 两个 novideo 坏条目 idx=69/82 的时长字段全缺）
            // 命中即不进池 → 用户永远刷不到；runtime repair→skip 仍兜底极罕见 type=0 坏媒体。
            let awemeType = aweme.awemeType()
            // 时长（wire 实证 f13=真实时长 ms；f12/f32 兜底；f22 是标志位非时长——v128 取值链被它污染，已修正）
            let dur = video.varint(13) ?? video.varint(12) ?? video.varint(32) ?? 0
            if awemeType != 0 {
                DYLog.shared.event("FEED skip-item a[\(ei)] id=\(id) type=\(awemeType) dur=\(dur) reason=type")
                DYLog.shared.count("filter_type")
                filtered += 1
                ei += 1
                continue
            }
            if dur == 0 {
                DYLog.shared.event("FEED skip-item a[\(ei)] id=\(id) type=\(awemeType) dur=\(dur) reason=nodur")
                DYLog.shared.count("filter_nodur")
                filtered += 1
                ei += 1
                continue
            }
            // 默认直链选链（v131，照抄 myDV resolveFinalPlayUrl(auto)+selectBestPlayUrl）：
            // 候选 = play_addr（video f1/f9，无水印播放版）url_list，空则退化 f8（=download_addr 水印版）。
            // ⚠️ 旧 v58 顺序 8→1→9 优先拿的是 download_addr（水印版，路径 /video/cn/mps/logo/ 实锤）
            // → 画面烧录漂移水印；myDV 播放只从 play_addr 选 → 无水印。v131 改正。
            // 候选内四级优先级（selectBestPlayUrl 原样）：
            //   ① douyinvod.com/[32hex]/[8hex]/ 签名直链（快+无水印）
            //   ② douyin.com/aweme/v1/play 重定向
            //   ③ douyinvod 带 signature=
            //   ④ 列表最后一个
            var candidates: [String] = []
            for pb in video.bytesFields(1) + video.bytesFields(9) {
                if let cand = Proto.parse(pb) {
                    let urls = Proto.urlList(cand, 0)
                    if !urls.isEmpty { candidates.append(contentsOf: urls); break }   // myDV：取第一个 url_list 非空的子消息（f1 优先 f9）
                }
            }
            if candidates.isEmpty {
                for pb in video.bytesFields(8) {
                    if let cand = Proto.parse(pb) {
                        let urls = Proto.urlList(cand, 0)
                        if !urls.isEmpty { candidates.append(contentsOf: urls); break }
                    }
                }
            }
            var normalized: [String] = []
            for raw in candidates {
                var u = raw
                if u.hasPrefix("//") { u = "https:" + u }
                let low = u.lowercased()
                guard low.hasPrefix("https://") || low.hasPrefix("http://") else { continue }
                normalized.append(u)
            }
            let chosen = Self.selectBestPlayUrl(normalized).flatMap { URL(string: $0) }
            // 重定向直链：play_addr（field 1/9，退化 8）url_list 里的 /aweme/v1/play/ 端点——
            // URL 不带时效签名，播放时请求→服务器现场 302→新鲜 CDN 直链（照 myDV selectBestPlayUrl 第②优先级）。
            var redirect: URL? = nil
            for pb in video.bytesFields(1) + video.bytesFields(9) + video.bytesFields(8) {
                guard let cand = Proto.parse(pb) else { continue }
                for raw in Proto.urlList(cand, 0) {
                    var u = raw
                    if u.hasPrefix("//") { u = "https:" + u }
                    guard u.lowercased().hasPrefix("https://") else { continue }
                    if u.contains("/aweme/v1/play/"), let url = URL(string: u) { redirect = url; break }
                }
                if redirect != nil { break }
            }
            // 每页首条 aweme 级字段 dump（v132 探针：定位 authentication_token/group_id 的 proto 字段号——
            // s13.e 未映射这两个字段，弹幕请求需要它们；token 形状=长字符串 bytes）
            if ei == 0 {
                let awemeDump = aweme.fields.keys.sorted().map { k -> String in
                    let vals = aweme.fields[k] ?? []
                    let desc = vals.map { v -> String in
                        switch v {
                        case .varint(let n): return "varint=\(n)"
                        case .bytes(let b): return "bytes=\(b.count)"
                        }
                    }
                    return "f\(k)[\(desc.joined(separator: ","))]"
                }.joined(separator: " ")
                DYLog.shared.log("FEED aweme-dump a[0] \(awemeDump)")
            }
            // 每视频一行紧凑诊断（替代旧 7 行 loop 噪音）
            DYLog.shared.log("FEED item a[\(ei)] id=\(id) type=\(awemeType) static=\(chosen != nil ? "ok" : "none") redirect=\(redirect != nil ? "ok" : "none") dur=\(dur)")
            // 四数组同点对齐 append（rawVideos/redirects 索引必须与 ids 一致，merge 按同下标对位）；
            // 静态无但重定向有的条目也收（urls 直接用重定向链，播放时 302 出新鲜直链）。
            guard let url = chosen ?? redirect else { DYLog.shared.count("parse_no_url"); ei += 1; continue }
            ids.append(id); urls.append(url); rawVideos.append(videoBytes); redirects.append(redirect); durations.append(Int(dur))
            if !loggedFirst {
                loggedFirst = true
                DYLog.shared.log("FEED first url[\(id)]: \(url.absoluteString.prefix(140))")
            }
            ei += 1
        }
        DYLog.shared.count("feed_aweme", by: awemeEntries.count)
        DYLog.shared.count("feed_usable", by: ids.count)
        DYLog.shared.count("feed_redirect", by: redirects.compactMap { $0 }.count)
        consumedIds.append(contentsOf: ids)
        DYLog.shared.log("FEED mobile page refresh_index=\(refreshIndex): awemes=\(awemeEntries.count) usable=\(ids.count) filtered=\(filtered) redirect=\(redirects.compactMap { $0 }.count) total_seen=\(consumedIds.count)")
        guard !ids.isEmpty else {
            DYLog.shared.event("FEED page refresh_index=\(refreshIndex): 0 usable videos — 检查 video/play_addr 字段号")
            PlaybackEngine.shared.reportFailure()
            return
        }
        PlaybackEngine.shared.merge(ids: ids, urls: urls,
                                    replaceExisting: false,
                                    autoPlay: PlaybackEngine.shared.urls.isEmpty,
                                    refresh: false,
                                    allRawVideos: rawVideos,
                                    allRedirectUrls: redirects,
                                    allDurations: durations)
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
    /// ⚠️ v128 起不再被播放路径调用：真机 video-dump 实锤移动端响应 field 21 是单 varint
    /// （URL 生成时刻时间戳），不是 bit_rate 子消息 → bytesFields(21/31) 恒空 → 恒返回 nil。
    /// v122 的 resolveFreshURL 曾依赖它"现取新鲜 URL"，被日志证伪（381 次 fallback static/0 次成功）。
    /// 保留作参考：若未来接入带 bit_rate 的响应（网页 JSON/其他 schema），此函数照 myDV highestQualityBitRate 可直接用。
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

    // MARK: - 选链（照抄 myDV VideoPlayUrlResolver.selectBestPlayUrl / isPathSigned，v131）

    private static let signedPathRegex = try? NSRegularExpression(pattern: "douyinvod\\.com/[0-9a-f]{32}/[0-9a-f]{8}/")

    /// isPathSigned 原样：douyinvod.com/[0-9a-f]{32}/[0-9a-f]{8}/ 即带签名直链。
    private static func isPathSigned(_ s: String) -> Bool {
        guard s.contains("douyinvod.com"), let re = signedPathRegex else { return false }
        let range = NSRange(s.startIndex..., in: s)
        return re.firstMatch(in: s, range: range) != nil
    }

    /// selectBestPlayUrl 四级优先级原样：
    /// ① 第一个带签名直链 ② 第一个 douyin.com/aweme/v1/play ③ 第一个 douyinvod+signature= ④ 最后一个。
    static func selectBestPlayUrl(_ list: [String]) -> String? {
        guard !list.isEmpty else { return nil }
        if let signed = list.first(where: { isPathSigned($0) }) { return signed }
        if let play = list.first(where: { $0.contains("douyin.com/aweme/v1/play") }) { return play }
        if let sig = list.first(where: { $0.contains("signature=") && $0.contains("douyinvod.com") }) { return sig }
        return list.last
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

    /// aweme_type（照抄 s13.e:371：依次探字段 {43,55,61}，第一个落在 [0,201) 的值即 type；
    /// 全缺时 myDV 模型默认 0 → 视为纯视频帖）。myDV filterPrimaryPlayableAwemes 只留 type==0。
    func awemeType() -> Int {
        for f in [43, 55, 61] {
            if let v = varint(f), v < 201 { return Int(v) }
        }
        return 0
    }

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
