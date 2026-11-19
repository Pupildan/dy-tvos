import Foundation

/// 单个直播间（web /webcast/feed/ + /webcast/room/web/enter/ JSON 字段映射，照抄 myDV
/// u11.java:1628-1695 + x04.java:327-333 + DataModelKt.java:40-41，2026-11-17 开发机探针全通）。
struct DYLiveRoom {
    let webRid: String          // 直播间路由 id（live.douyin.com/<webRid>，进房钥匙）
    let roomId: String          // 房间数字 id（enter 响应 room_id；feed 阶段可能为空）
    let title: String
    let coverUrl: String
    let ownerName: String
    let ownerAvatar: String
    let userCount: String       // 观看人数（字符串，接口直接给）
    let hlsUrls: [String: String]   // 清晰度→URL（FULL_HD1/HD1/SD2/SD1），HLS(.m3u8) tvOS AVPlayer 原生支持
    let flvUrls: [String: String]   // 清晰度→URL（FLV，tvOS 播不了，仅备用）

    /// 是否有可用拉流地址
    var hasStream: Bool { !hlsUrls.isEmpty || !flvUrls.isEmpty }
}

/// 直播客户端（第一版：匿名拉流播放，无弹幕）。
/// 关键结论（开发机探针 `_tmp/live_probe.js` 2026-11-17 实锤）：live.douyin.com **不撞作品墙**——
/// feed/enter 与现有 feed/弹幕/评论同款 `a_bogus` 签名（getABogus）+ 匿名 ttwid 即可，返回 status_code=0 + 真 HLS URL。
/// 复用：DYSigner（a_bogus）+ DYDanmakuClient.ensureTTWID（匿名 ttwid）+ 最小头（绝不加 sec-ch-ua，v157 铁律）。
final class DYLiveClient {
    static let shared = DYLiveClient()

    private let host = "https://live.douyin.com"
    private let feedPath = "/webcast/feed/"
    private let enterPath = "/webcast/room/web/enter/"
    /// myDV 直播链 QQBrowser UA（i11.java:362 / kq2 原文）——签名第 4 参 + 请求头必须一致
    static let liveUA = "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.97 Safari/537.36 Core/1.116.567.400 QQBrowser/19.7.6764.400"

    /// 清晰度优先级（DataModelKt PULL_URL_MAP_ORDER_HIGH_TO_LOW）
    private static let qualityOrder = ["FULL_HD1", "HD1", "SD2", "SD1"]
    /// 清晰度显示名
    static func qualityName(_ key: String) -> String {
        switch key {
        case "FULL_HD1": return "蓝光"
        case "HD1": return "超清"
        case "SD2": return "高清"
        case "SD1": return "标清"
        default: return key
        }
    }

    private var feedCache: [DYLiveRoom] = []
    private var feedInflight = false
    /// 翻页游标（探针实锤：响应 extra.max_time 毫秒时间戳 + extra.has_more，逐页前进）
    private var feedMaxTime: String = "0"
    private var feedHasMore = true
    /// 跨页去重（抖音混推相邻页有重叠，page2-dup 只 2 新——必须按 webRid 全局去重）
    private var seenWebRids = Set<String>()

    /// 已累积直播间（feedCache 的只读快照；直播流屏数据源）
    var rooms: [DYLiveRoom] { feedCache }
    var isLoadingMore: Bool { feedInflight }
    /// 是否还有更多页（供 UI 在冷门房过滤光整页时判断要不要链式续翻）
    var hasMore: Bool { feedHasMore }

    // MARK: - 直播间列表（游标翻页，无限刷）

    /// 首页（maxtime=0）。onDone 主队列回调本页新增房间（空数组=失败/无数据）。
    func fetchLiveFeed(force: Bool = false, onDone: @escaping ([DYLiveRoom]) -> Void) {
        if !force, !feedCache.isEmpty { onDone([]); return }
        feedMaxTime = "0"
        feedHasMore = true
        seenWebRids.removeAll()
        feedCache.removeAll()
        loadMore(onDone: onDone)
    }

    /// 翻下一页（用 feedMaxTime 游标）。onDone 主队列回调**本页新增**（去重后）房间；空=无更多/在飞/失败。
    /// 直播流屏滚到倒数 ~5 个时调用（照 PlaybackEngine.triggerNeedMore 末尾翻页）。
    func loadMore(onDone: @escaping ([DYLiveRoom]) -> Void) {
        guard !feedInflight else { onDone([]); return }
        guard feedHasMore else { onDone([]); return }
        feedInflight = true
        let maxTime = feedMaxTime
        DYDanmakuClient.shared.ensureTTWID { [weak self] in
            guard let self else { return }
            self.fetchFeedInternal(maxTime: maxTime, onDone: onDone)
        }
    }

    private func fetchFeedInternal(maxTime: String, onDone: @escaping ([DYLiveRoom]) -> Void) {
        // 参数照抄 myDV u11.java:1628-1695（首页首页卡片配方）；maxtime=翻页游标（0=首页）
        var p: [(String, String)] = [
            ("device_platform", "web"),
            ("app_name", "douyin_web"),
            ("live_id", "1"),
            ("need_map", "1"),
            ("liveid", "1"),
            ("is_draw", "1"),
            ("inner_from_drawer", "0"),
            ("custom_count", "20"),
            ("action", "load_more"),
            ("action_type", "loadmore"),
            ("enter_source", "web_homepage_hot_web_live_card"),
            ("source_key", "web_homepage_hot_web_live_card"),
            ("is_ssr", "true"),
            ("maxtime", maxTime),
            ("aid", "6383"),
            ("language", "zh-CN"),
            ("tz_name", "Asia/Shanghai"),
            ("msToken", Self.randomMsToken()),
        ]
        let baseQuery = p.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        guard let sr = DYSigner.shared.sign(query: baseQuery, data: "", path: feedPath, ua: Self.liveUA) else {
            DYLog.shared.log("LIVE feed sign fail")
            feedInflight = false
            DispatchQueue.main.async { onDone([]) }
            return
        }
        var finalQuery = baseQuery
        if !sr.value.isEmpty { finalQuery += "&a_bogus=\(sr.value)" }
        guard let url = URL(string: "\(host)\(feedPath)?\(finalQuery)") else {
            feedInflight = false
            DispatchQueue.main.async { onDone([]) }
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue(Self.liveUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
        req.setValue("\(host)/", forHTTPHeaderField: "Referer")
        let ttwid = DYDanmakuClient.shared.ttwidValue
        if !ttwid.isEmpty { req.setValue("ttwid=\(ttwid)", forHTTPHeaderField: "Cookie") }

        DYLog.shared.log("LIVE feed GET bogus_len=\(sr.value.count) ttwid=\(ttwid.isEmpty ? 0 : ttwid.count)")
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            self.feedInflight = false
            let httpStatus = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard err == nil, httpStatus == 200, let data, !data.isEmpty,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  (obj["status_code"] as? Int ?? -1) == 0 else {
                DYLog.shared.event("LIVE feed fail http=\(httpStatus) err=\(err?.localizedDescription ?? "nil")")
                DispatchQueue.main.async { onDone([]) }
                return
            }
            let list = obj["data"] as? [[String: Any]] ?? []
            // 翻页游标（探针实锤：extra.max_time 毫秒时间戳 + extra.has_more，恒为 Bool）
            let extra = obj["extra"] as? [String: Any] ?? [:]
            if let mt = extra["max_time"] as? String, !mt.isEmpty {
                feedMaxTime = mt
            } else if let mt = (extra["max_time"] as? NSNumber)?.stringValue, !mt.isEmpty {
                feedMaxTime = mt
            }
            feedHasMore = (extra["has_more"] as? Bool) ?? true
            // 跨页去重追加（抖音混推相邻页有重叠）
            var fresh: [DYLiveRoom] = []
            var filteredCold = 0
            for e in list {
                guard let room = Self.parseRoom(e), !seenWebRids.contains(room.webRid) else { continue }
                seenWebRids.insert(room.webRid)
                // 冷门房过滤：观看数 <500 的房不进滑动列表（用户拍板，去首页池长尾冷门房）
                if Self.viewerCountValue(room.userCount) < Self.minViewerCount {
                    filteredCold += 1
                    continue
                }
                feedCache.append(room)
                fresh.append(room)
            }
            DYLog.shared.event("LIVE feed ok page maxtime=\(maxTime) got=\(list.count) fresh=\(fresh.count) coldFiltered=\(filteredCold) total=\(feedCache.count) hasMore=\(feedHasMore ? 1 : 0)")
            DispatchQueue.main.async { onDone(fresh) }
        }.resume()
    }

    // MARK: - 进房拉流

    /// 进房取拉流地址（web /webcast/room/web/enter/）。onDone 主队列回调带 hlsUrls 的房间。
    func enterRoom(_ webRid: String, onDone: @escaping (DYLiveRoom?) -> Void) {
        guard !webRid.isEmpty else { DispatchQueue.main.async { onDone(nil) }; return }
        DYDanmakuClient.shared.ensureTTWID { [weak self] in
            guard let self else { return }
            self.enterInternal(webRid: webRid, onDone: onDone)
        }
    }

    private func enterInternal(webRid: String, onDone: @escaping (DYLiveRoom?) -> Void) {
        // 参数照抄 myDV x04.java:327-333（enter 配方：web_rid + 空 msToken）
        let p: [(String, String)] = [
            ("aid", "6383"),
            ("app_name", "douyin_web"),
            ("live_id", "1"),
            ("device_platform", "web"),
            ("language", "zh-CN"),
            ("browser_language", "zh-CN"),
            ("browser_platform", "Win32"),
            ("browser_name", "Chrome"),
            ("browser_version", "125.0.0.0"),
            ("web_rid", webRid),
            ("msToken", ""),
        ]
        let baseQuery = p.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        // enter 的签名 path=enterPath，referer=https://live.douyin.com/<webRid>（探针实证）
        guard let sr = DYSigner.shared.sign(query: baseQuery, data: "", path: enterPath, ua: Self.liveUA) else {
            DYLog.shared.log("LIVE enter sign fail webRid=\(webRid)")
            DispatchQueue.main.async { onDone(nil) }
            return
        }
        var finalQuery = baseQuery
        if !sr.value.isEmpty { finalQuery += "&a_bogus=\(sr.value)" }
        guard let url = URL(string: "\(host)\(enterPath)?\(finalQuery)") else {
            DispatchQueue.main.async { onDone(nil) }
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue(Self.liveUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
        req.setValue("\(host)/\(webRid)", forHTTPHeaderField: "Referer")
        let ttwid = DYDanmakuClient.shared.ttwidValue
        if !ttwid.isEmpty { req.setValue("ttwid=\(ttwid)", forHTTPHeaderField: "Cookie") }

        DYLog.shared.log("LIVE enter GET webRid=\(webRid) bogus_len=\(sr.value.count)")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let httpStatus = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard err == nil, httpStatus == 200, let data, !data.isEmpty,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  (obj["status_code"] as? Int ?? -1) == 0 else {
                DYLog.shared.event("LIVE enter fail http=\(httpStatus) err=\(err?.localizedDescription ?? "nil")")
                DispatchQueue.main.async { onDone(nil) }
                return
            }
            // enter 响应：data.data[0]（LiveRoomEnterData.data 列表）或 data.room
            let dataObj = obj["data"] as? [String: Any] ?? [:]
            var roomObj: [String: Any] = [:]
            if let arr = dataObj["data"] as? [[String: Any]], let first = arr.first {
                roomObj = first
            } else if let r = dataObj["room"] as? [String: Any] {
                roomObj = r
            }
            guard !roomObj.isEmpty else {
                DYLog.shared.event("LIVE enter no room webRid=\(webRid)")
                DispatchQueue.main.async { onDone(nil) }
                return
            }
            let room = Self.parseRoom(roomObj, fallbackWebRid: webRid)
            DYLog.shared.event("LIVE enter ok webRid=\(webRid) roomId=\(room?.roomId ?? "?") hls=\(room?.hlsUrls.count ?? 0)")
            DispatchQueue.main.async { onDone(room) }
        }.resume()
    }

    // MARK: - 解析

    /// 冷门房过滤阈值（用户拍板 2026-11-19：观看数 <500 的房不进滑动列表）。
    /// 探针 live_pool_dist_probe.js 实锤首页池是爆款+长尾混合流，一半房 <1000 人、底部有 1~8 人极冷房；
    /// <500 过滤掉最冷尾（26 房里留 ~62%），换 enter_source 池子走不通（其他值全 0 房），只能客户端过滤。
    static let minViewerCount = 500

    /// 观看数展示字符串转数值（"253493"→253493、"1.2万"→12000、"38"→38），供冷门房过滤比较。
    static func viewerCountValue(_ s: String) -> Int {
        let str = s.trimmingCharacters(in: .whitespaces)
        if str.contains("万") {
            let n = Double(str.replacingOccurrences(of: "万", with: "")) ?? 0
            return Int(n * 10000)
        }
        let digits = str.filter { $0.isNumber }
        return Int(digits) ?? 0
    }

    /// 从 feed 项（{web_rid, data:LiveRoom}）或 enter room 对象解析。hls/flv 来自 stream_url。
    static func parseRoom(_ e: [String: Any], fallbackWebRid: String = "") -> DYLiveRoom? {
        // feed 项把 LiveRoom 放在 "data" 子对象；enter 直接是 room 对象
        let room = (e["data"] as? [String: Any]) ?? e
        var webRid = (e["web_rid"] as? String) ?? (room["web_rid"] as? String) ?? fallbackWebRid
        if webRid.isEmpty {
            webRid = (room["id_str"] as? String) ?? (room["enter_room_id"] as? String) ?? fallbackWebRid
        }
        guard !webRid.isEmpty else { return nil }
        let roomId = (room["room_id"] as? String) ?? ((room["room_id"] as? NSNumber)?.stringValue) ?? ((room["id_str"] as? String) ?? "")
        let title = (room["title"] as? String) ?? ""
        var cover = ""
        if let cov = room["cover"] as? [String: Any], let ul = cov["url_list"] as? [String] {
            cover = ul.first(where: { $0.hasPrefix("http") }) ?? ""
        }
        var ownerName = ""
        var ownerAvatar = ""
        if let owner = room["owner"] as? [String: Any] {
            ownerName = (owner["nickname"] as? String) ?? ""
            if let av = owner["avatar_thumb"] as? [String: Any], let ul = av["url_list"] as? [String] {
                ownerAvatar = ul.first(where: { $0.hasPrefix("http") }) ?? ""
            } else if let av = owner["avatar_medium"] as? [String: Any], let ul = av["url_list"] as? [String] {
                ownerAvatar = ul.first(where: { $0.hasPrefix("http") }) ?? ""
            }
        }
        var userCount = ""
        if let uc = room["user_count_str"] as? String {
            userCount = uc
        } else if let st = room["room_view_stats"] as? [String: Any], let dc = st["display_value"] as? String {
            userCount = dc
        } else if let uc = (room["user_count"] as? NSNumber)?.stringValue {
            userCount = uc
        }
        var hls: [String: String] = [:]
        var flv: [String: String] = [:]
        if let su = room["stream_url"] as? [String: Any] {
            if let h = su["hls_pull_url_map"] as? [String: String] { hls = h }
            if let f = su["flv_pull_url"] as? [String: String] { flv = f }
        }
        return DYLiveRoom(webRid: webRid, roomId: roomId, title: title, coverUrl: cover,
                          ownerName: ownerName, ownerAvatar: ownerAvatar, userCount: userCount,
                          hlsUrls: hls, flvUrls: flv)
    }

    /// 按清晰度优先级选最佳 HLS URL（DataModelKt FULL_HD1→HD1→SD2→SD1）。
    static func bestHlsUrl(_ hlsUrls: [String: String]) -> String {
        for q in qualityOrder {
            if let u = hlsUrls[q], !u.isEmpty { return u }
        }
        return hlsUrls.values.first ?? ""
    }

    static func randomMsToken() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        var s = ""
        for _ in 0..<107 { s.append(chars.randomElement()!) }
        return s
    }
}
