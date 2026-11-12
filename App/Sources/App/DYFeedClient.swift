import Foundation

/// 原生抖音直连客户端：替代 WebView 泵。
/// 流程：URLSession 访问 douyin.com 收 Set-Cookie(ttwid 匿名可取)
///   → 拼 feed query → DYSigner 现场算 a_bogus → 带 cookie/Referer/UA 请求
///   → 解析 aweme_list[].video.play_addr.url_list → PlaybackEngine
/// 无限刷：refresh_index 递增重新签名（每请求新鲜签名，天然无限）。
/// 无感刷新：播放失败/整批过期 → 重签重拉当前批，按 aweme_id 对齐回原位置。
final class DYFeedClient {
    static let shared = DYFeedClient()

    private let session: URLSession
    private var refreshIndex = 0
    private var booted = false
    /// 有序 awemeId -> 直链（保持 feed 顺序）
    private var ordered: [(id: String, url: URL)] = []

    private let host = "https://www.douyin.com"
    private let feedPath = "/aweme/v2/web/module/feed/"
    private let baseQuery = "device_platform=webapp&aid=6383&channel=channel_pc_web&module_id=3003101&count=20&filterGids=&presented_ids=&refer_id=&refer_type=10&pc_client_type=1&pc_libra_divert=Mac&support_h265=0&support_dash=0&cpu_core_num=4&version_code=170400&video_type_select=1&filter_warn=0&need_fix_st=0&web_page_type=0&os=mac&pull_type=2&is_follow_live=0&poi_data=0&whale_cut_token=&globalId=tobid&msToken="

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpShouldSetCookies = true
        cfg.httpAdditionalHeaders = [
            "Referer": "https://www.douyin.com/",
            "User-Agent": WebKitShellViewController.desktopUA,
        ]
        session = URLSession(configuration: cfg)
    }

    /// 启动：等签名器就绪 → 收 cookie → 拉第一批（自动播 index 0）。
    func start() {
        DYSigner.shared.onReady = { [weak self] in
            self?.bootstrapThenFetch()
        }
        // 签名器可能已就绪（initialize 幂等）
        DYSigner.shared.initialize()
    }

    private func bootstrapThenFetch() {
        guard !booted else { return }
        booted = true
        // 1) cookie 引导：请求主页，HTTPCookieStorage 自动收 ttwid 等（匿名）
        guard let url = URL(string: host + "/") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        session.dataTask(with: req) { [weak self] _, resp, err in
            if let err { DYLog.shared.log("FEED bootstrap err: \(err.localizedDescription)") }
            let ck = HTTPCookieStorage.shared.cookies(for: url!)
            let names = ck.map { $0.name }.joined(separator: ",")
            DYLog.shared.log("FEED cookies: \(ck.count) [\(String(names.prefix(120)))]")
            self?.fetchPage(initial: true)
        }.resume()
    }

    /// 拉一页 feed（签名直连）。
    /// initial=true → 第一批（引擎自动播 index0）；否则追加页（保持当前 index）。
    func fetchPage(initial: Bool, refresh: Bool = false) {
        guard DYSigner.shared.ready else {
            DYLog.shared.log("FEED skip: signer not ready")
            return
        }
        if initial || refresh { /* 保持当前页码 */ } else { refreshIndex += 1 }
        let idx = max(1, refreshIndex == 0 ? 1 : refreshIndex)
        let query = baseQuery + "&refresh_index=\(idx)"
        guard let bogus = DYSigner.shared.sign(query: query, data: "", uri: feedPath) else {
            DYLog.shared.log("FEED sign fail (page \(idx))")
            PlaybackEngine.shared.reportFailure()
            return
        }
        let urlString = host + feedPath + "?" + query + "&a_bogus=" + bogus
        guard let url = URL(string: urlString) else { return }
        DYLog.shared.log("FEED GET page=\(idx) refresh=\(refresh) bogus_len=\(bogus.count)")

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            if let err { DYLog.shared.log("FEED http err: \(err.localizedDescription)"); return }
            guard let http = resp as? HTTPURLResponse else { return }
            guard let data, !data.isEmpty else {
                DYLog.shared.log("FEED empty body (page \(idx)) code=\(http.statusCode)")
                return
            }
            self.parse(data: data, page: idx, initial: initial, refresh: refresh)
        }.resume()
    }

    /// 解析 feed JSON → 直链列表 → 注入引擎。
    private func parse(data: Data, page: Int, initial: Bool, refresh: Bool) {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = (obj["aweme_list"] as? [[String: Any]]) ?? (obj["awemes"] as? [[String: Any]]) else {
            DYLog.shared.log("FEED parse fail (page \(page), \(data.count)B)")
            return
        }
        var added = 0
        for a in list {
            guard let id = a["aweme_id"] as? String else { continue }
            if ordered.contains(where: { $0.id == id }) { continue } // 去重保序
            let video = a["video"] as? [String: Any] ?? [:]
            let pa = (video["play_addr"] as? [String: Any]) ?? (video["download_addr"] as? [String: Any]) ?? [:]
            guard let ul = pa["url_list"] as? [String] else { continue }
            for raw in ul {
                var u = raw
                if u.hasPrefix("//") { u = "https:" + u }
                if u.contains("/aweme/v1/play/") { continue } // 403 坏端点
                if let url = URL(string: u) {
                    ordered.append((id, url))
                    added += 1
                    break // 每个 aweme 取第一条可用直链
                }
            }
        }
        DYLog.shared.log("FEED page \(page): awemes=\(list.count) new=\(added) total=\(ordered.count)")
        guard !ordered.isEmpty else { return }
        let urls = ordered.map { $0.url }
        let ids = ordered.map { $0.id }
        PlaybackEngine.shared.setURLs(urls, awemeIds: ids,
                                      isNewBatch: initial, isRefresh: refresh)
    }

    /// 播放失败/过期时重拉当前批（引擎回调）。
    func refetchCurrent() {
        fetchPage(initial: false, refresh: true)
    }
}
