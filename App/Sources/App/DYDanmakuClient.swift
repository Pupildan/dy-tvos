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
    /// web 公共参数（v133 探针实锤：缺 aid=6383 等一律 status_code=3 "AppId不合法"）
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
    /// 分段窗口（v138 探针实锤：单次响应 ~460 条上限，60s 窗口可取全量）
    private static let segmentWindowMs: Int = 60_000
    /// 响应上限阈值（v140：段返回 ≥450 条视为被截断，自动对半递归拆分）
    private static let capThreshold = 450

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

    /// 取 awemeId 的弹幕（v138 分段版：60s 窗口顺序请求——单次响应有 ~460 条上限，
    /// 长视频一次请求只拿到第一段就断流；分段合并去重，开发机探针实锤 186s 视频 458→1183 条）。
    /// onSegment 每段增量回调（主队列，段内按 offset_time 有序、段间时间递增）；
    /// completion 全部段完成后回调（主队列）。缓存优先；inflight 去重。
    func items(for awemeId: String, durationMs: Int,
               onSegment: @escaping ([DYDanmakuItem]) -> Void,
               completion: @escaping () -> Void) {
        guard !awemeId.isEmpty else { completion(); return }
        if let hit = cache[awemeId] {
            DispatchQueue.main.async { onSegment(hit) }
            completion(); return
        }
        guard !inflight.contains(awemeId) else { completion(); return }
        inflight.insert(awemeId)
        queue.async { [weak self] in
            guard let self else { return }
            self.ensureTTWIDInternal { [weak self] in
                self?.fetch(awemeId: awemeId, durationMs: durationMs, onSegment: { seg in
                    DispatchQueue.main.async { onSegment(seg) }
                }, completion: { [weak self] allItems in
                    guard let self else { return }
                    self.queue.async {
                        self.inflight.remove(awemeId)
                        if !allItems.isEmpty { self.cache[awemeId] = allItems }
                        DispatchQueue.main.async {
                            completion()
                        }
                    }
                })
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
            self?.ensureTTWIDInternal { done() }
        }
    }

    // MARK: - ttwid 匿名注册（照抄 u11.A 原文：POST ttwid.bytedance.com/ttwid/union/register/）

    private func ensureTTWIDInternal(_ done: @escaping () -> Void) {
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

    /// 分段取回（v140 自适应切分版）：
    /// - 单次响应 ~460 条硬上限（探针实锤）→ 一次请求拿不到全量，但**自适应切分**可以等价拿全：
    ///   某段返回 ≥ capThreshold 条（=被截断）自动对半再拆，直到每段都在上限内。
    /// - 段间 0.15s 节流 + 失败段重试一次（v139）。
    /// - onSegment 每段增量回调（主队列，可能乱序——Overlay 用 id 去重扫描容忍）；completion 全量合并数组（主队列）。
    private func fetch(awemeId: String, durationMs: Int,
                       onSegment: @escaping ([DYDanmakuItem]) -> Void,
                       completion: @escaping ([DYDanmakuItem]) -> Void) {
        let d = max(0, durationMs)
        guard d > 0 else { completion([]); return }
        var merged: [DYDanmakuItem] = []
        var seen = Set<String>()
        var failedWindows: [(Int, Int)] = []

        // 单窗口请求。done(ok, items)——ok=false 表示被拒/解析失败（交重试）；items 为原始解析结果（未去重）。
        func requestWindow(start: Int, end: Int, done: @escaping (_ ok: Bool, _ items: [DYDanmakuItem]) -> Void) {
            let p: [(String, String)] = Self.webCommon + [
                ("app_name", "aweme"),
                ("format", "json"),
                ("group_id", awemeId),
                ("item_id", awemeId),
                ("start_time", String(start)),
                ("end_time", String(end)),
                ("duration", String(d)),
                ("authentication_token", ""),   // 传空即可（探针实锤）
                ("pc_libra_divert", "Windows"),
                ("support_h265", "0"),
                ("support_dash", "1"),
                ("version_code", "170400"),
                ("version_name", "17.4.0"),
                ("msToken", Self.randomMsToken()),
                ("screen_width", "2560"),
                ("screen_height", "1440"),
                ("cpu_core_num", "24"),
                ("device_memory", "8"),
            ]
            let ts = String(Int(Date().timeIntervalSince1970))
            let baseQuery = p.map { "\($0.0)=\($0.1)" }.joined(separator: "&") + "&timestamp=\(ts)"
            guard let sr = DYSigner.shared.sign(query: baseQuery, data: "", path: path, ua: DYDanmakuClient.webUA) else {
                DYLog.shared.log("DANM sign fail (not ready)")
                done(false, []); return
            }
            var finalQuery = baseQuery
            if !sr.value.isEmpty { finalQuery += "&a_bogus=\(sr.value)" }
            guard let url = URL(string: "\(host)\(path)?\(finalQuery)") else { done(false, []); return }
            var req = URLRequest(url: url)
            req.timeoutInterval = 12
            req.setValue(DYDanmakuClient.webUA, forHTTPHeaderField: "User-Agent")
            req.setValue("*/*", forHTTPHeaderField: "Accept")
            if !ttwid.isEmpty { req.setValue("ttwid=\(ttwid)", forHTTPHeaderField: "Cookie") }
            req.setValue("\(host)/video/\(awemeId)", forHTTPHeaderField: "Referer")

            DYLog.shared.log("DANM get id=\(awemeId) [\(start / 1000)-\(end / 1000)s] ttwid=\(ttwid.isEmpty ? 0 : ttwid.count)")
            session.dataTask(with: req) { data, resp, err in
                let httpStatus = (resp as? HTTPURLResponse)?.statusCode ?? -1
                guard err == nil, httpStatus == 200, let data, !data.isEmpty,
                      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      (obj["status_code"] as? Int ?? -1) == 0 else {
                    DYLog.shared.log("DANM segment [\(start / 1000)-\(end / 1000)s] fail http=\(httpStatus)")
                    DispatchQueue.main.async { done(false, []) }
                    return
                }
                let list = obj["danmaku_list"] as? [[String: Any]] ?? []
                var items: [DYDanmakuItem] = []
                for e in list {
                    guard let text = e["text"] as? String, !text.isEmpty else { continue }
                    let did = (e["danmaku_id"] as? NSNumber)?.stringValue ?? (e["danmaku_id"] as? String ?? "")
                    guard !did.isEmpty else { continue }
                    let off = (e["offset_time"] as? NSNumber)?.doubleValue ?? 0
                    items.append(DYDanmakuItem(danmakuId: did, offsetTime: off, text: text))
                }
                DispatchQueue.main.async { done(true, items) }
            }.resume()
        }

        // 去重入库 + 增量回调
        func accept(_ items: [DYDanmakuItem]) {
            var fresh: [DYDanmakuItem] = []
            for it in items {
                guard !seen.contains(it.danmakuId) else { continue }
                seen.insert(it.danmakuId)
                fresh.append(it)
            }
            guard !fresh.isEmpty else { return }
            fresh.sort { $0.offsetTime < $1.offsetTime }
            merged.append(contentsOf: fresh)
            DYLog.shared.count("dm_items", by: fresh.count)
            onSegment(fresh)
        }

        /// 取 [start,end) 区间：按 window 切片顺序请求；命中上限（≥capThreshold）自动对半递归拆分。
        func fetchRange(start: Int, end: Int, depth: Int, done: @escaping () -> Void) {
            if start >= end { done(); return }
            let chunkEnd = min(start + Self.segmentWindowMs, end)
            requestWindow(start: start, end: chunkEnd) { [weak self] ok, items in
                if !ok {
                    failedWindows.append((start, chunkEnd))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { fetchRange(start: chunkEnd, end: end, depth: depth, done: done) }
                    return
                }
                if items.count >= Self.capThreshold, chunkEnd - start > 10_000, depth < 4 {
                    // 命中响应上限=截断 → 对半递归拆分（已回的 458 条也会被 halves 覆盖，seen 去重兜底）
                    DYLog.shared.log("DANM cap-hit [\(start / 1000)-\(chunkEnd / 1000)s] n=\(items.count) → split")
                    let mid = (start + chunkEnd) / 2
                    fetchRange(start: start, end: mid, depth: depth + 1) {
                        fetchRange(start: mid, end: chunkEnd, depth: depth + 1) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { fetchRange(start: chunkEnd, end: end, depth: depth, done: done) }
                        }
                    }
                    return
                }
                accept(items)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { fetchRange(start: chunkEnd, end: end, depth: depth, done: done) }
            }
        }

        // 失败段重试轮（v139 保持）：0.4s 间隔逐个重试一次
        func runRetries() {
            guard !failedWindows.isEmpty else {
                DYLog.shared.event("DANM all-segments done id=\(awemeId) total=\(merged.count) retry=0")
                completion(merged)
                return
            }
            var remaining = failedWindows
            DYLog.shared.event("DANM retry \(failedWindows.count) failed segments id=\(awemeId)")
            func retryNext() {
                guard !remaining.isEmpty else {
                    DYLog.shared.event("DANM all-segments done id=\(awemeId) total=\(merged.count) retry=\(failedWindows.count)")
                    completion(merged)
                    return
                }
                let (s, e) = remaining.removeFirst()
                requestWindow(start: s, end: e) { [weak self] ok, items in
                    if ok { accept(items) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { retryNext() }
                }
            }
            retryNext()
        }

        fetchRange(start: 0, end: d, depth: 0) { [weak self] in
            guard let self else { return }
            runRetries()
        }
    }

    static func randomMsToken() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<126).map { _ in chars.randomElement()! }) + "=="
    }
}
