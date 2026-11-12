import Foundation

/// 原生抖音直连客户端（模板回放方案）：
/// 泵捕获的完整 module/feed URL 作为模板（含全部正确参数），
/// 原生请求时替换 refresh_index（翻页）/ presented_ids（排除已看）/ 现场重签 a_bogus，其余原样。
/// 无限刷：refresh_index 直调，每页全新推荐（不依赖隐藏页面滚动）。
/// 无感刷新：播放失败/过期 → 同页重签重拉，按 aweme_id 对齐。
final class DYFeedClient {
    static let shared = DYFeedClient()

    private let session: URLSession
    private var pageIndex = 1
    private var booted = false
    private var signerReady = false
    private var consumed = Set<String>()

    /// 泵捕获的完整 feed 请求 URL 模板（含全部正确参数）。
    var templateURL: String? {
        didSet { tryStart() }
    }

    private let host = "https://www.douyin.com"
    private let feedPath = "/aweme/v2/web/module/feed/"
    /// 与 shim navigator.userAgent 一致（a_bogus 签名绑定 UA）
    static let requestUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// 页面真实请求头（HDS 捕获，module/feed 关联）——原生请求逐个复刻
    private var pageHeaders: [String: String] = [:]
    private var headerRetryFired = false

    func setPageHeader(name: String, value: String) {
        pageHeaders[name] = value
        DYLog.shared.log("FEED page header stored: \(name)=\(String(value.prefix(40))) (\(pageHeaders.count) total)")
        // 修竞态：首个原生请求早于头入库（被拒）。头集齐后补发一次带头翻页。
        if !headerRetryFired, pageHeaders.count >= 3, signerReady, templateURL != nil {
            headerRetryFired = true
            DYLog.shared.log("FEED headers ready, fire native page with headers")
            fetchNativePage(initial: false, refresh: false)
        }
    }

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpShouldSetCookies = true
        // 对齐页面 XHR 的请求头（dex 实证 myDV 同款）——网关校验的一部分
        cfg.httpAdditionalHeaders = [
            "Referer": "https://www.douyin.com/",
            "User-Agent": DYFeedClient.requestUA,
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Cache-Control": "no-cache",
            "Pragma": "no-cache",
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-origin",
        ]
        session = URLSession(configuration: cfg)
    }

    /// 启动：等签名器就绪 + 模板到手 → 原生拉第一批。
    func start() {
        DYSigner.shared.onReady = { [weak self] in
            self?.signerReady = true
            self?.tryStart()
        }
        DYSigner.shared.initialize()
    }

    private func tryStart() {
        guard signerReady, templateURL != nil, !booted else { return }
        booted = true
        DYLog.shared.log("FEED native pipeline armed (template captured)")
        fetchNativePage(initial: true, refresh: false)
    }

    /// 基于模板拉一页。initial=首批（自动播）；refresh=过期重拉（对齐原位置）。
    func fetchNativePage(initial: Bool, refresh: Bool = false) {
        DYLog.shared.log("FEED native fetch called initial=\(initial) refresh=\(refresh) hasTemplate=\(templateURL != nil) signerReady=\(DYSigner.shared.ready)")
        guard let tpl = templateURL else {
            DYLog.shared.log("FEED skip: no template yet")
            return
        }
        if !initial && !refresh { pageIndex += 1 }
        let idx = max(1, pageIndex)
        // 先把 WebView cookie 罐（msToken 等页面级 cookie）同步进共享罐，原生请求才能带上
        DYTransferWebViewCookies()

        guard var comps = URLComponents(string: tpl) else {
            DYLog.shared.log("FEED template parse fail")
            return
        }
        var items = comps.queryItems ?? []
        // refresh_index → 翻页页码
        items = items.map { $0.name == "refresh_index" ? URLQueryItem(name: "refresh_index", value: String(idx)) : $0 }
        // presented_ids → 已消费 id（排除重复推荐）
        let consumedList = PlaybackEngine.shared.consumedIds.joined(separator: ",")
        items = items.map { $0.name == "presented_ids" ? URLQueryItem(name: "presented_ids", value: consumedList) : $0 }
        // 去掉旧 a_bogus（现场重签）
        items.removeAll { $0.name == "a_bogus" }
        comps.queryItems = items
        guard let base = comps.url, let query = base.query else { return }

        guard let sr = DYSigner.shared.sign(query: query, data: "", uri: feedPath) else {
            DYLog.shared.log("FEED sign fail (page \(idx))")
            PlaybackEngine.shared.reportFailure()
            return
        }
        // a_bogus 需与页面一致做百分号编码（+/= → %2B/%3D，/ → %2F）
        let bogus = sr.value
        let enc = bogus.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_~.")) ?? bogus
        let urlString = base.absoluteString + "&a_bogus=" + enc
        guard let url = URL(string: urlString) else {
            DYLog.shared.log("FEED URL parse fail len=\(urlString.count) head=\(String(urlString.prefix(120)))")
            return
        }
        DYLog.shared.log("FEED native GET page=\(idx) initial=\(initial) refresh=\(refresh) bogus_len=\(bogus.count) presented=\(consumedList.count) sec_headers=\(sr.headers.count)")

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        // 页面真实请求头（Content-Type/uifid/x-secsdk-csrf-token 等）——网关路由校验所需
        for (k, v) in pageHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }
        // bdms 注入的安全头（x-secsdk-web-signature 等）——签名流程捕获到的也带上
        for (k, v) in sr.headers {
            req.setValue(v, forHTTPHeaderField: k)
        }
        session.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            if let err { DYLog.shared.log("FEED http err: \(err.localizedDescription)"); return }
            guard let data, !data.isEmpty else {
                DYLog.shared.log("FEED empty body (page \(idx))")
                return
            }
            self.parse(data: data, page: idx, initial: initial, refresh: refresh)
        }.resume()
    }

    /// 解析 feed JSON → aweme_id+直链 → 引擎统一合并。
    private func parse(data: Data, page: Int, initial: Bool, refresh: Bool) {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = (obj["aweme_list"] as? [[String: Any]]) ?? (obj["awemes"] as? [[String: Any]]) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary \(data.count)B>"
            DYLog.shared.log("FEED parse fail (page \(page)) body=\(String(body.prefix(200)))")
            PlaybackEngine.shared.reportFailure()
            return
        }
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
        DYLog.shared.log("FEED native page \(page): awemes=\(list.count) usable=\(ids.count)")
        guard !ids.isEmpty else { return }
        PlaybackEngine.shared.merge(ids: ids, urls: urls,
                                    replaceExisting: refresh,
                                    autoPlay: initial,
                                    refresh: refresh)
    }

    /// 播放失败/过期重拉（引擎回调）。
    func refetchCurrent() {
        fetchNativePage(initial: false, refresh: true)
    }
}
