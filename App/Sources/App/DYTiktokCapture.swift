import Foundation
import UIKit

/// TikTok（国际版）推荐流离屏 WebView 数据泵（v223）。
/// TikTok 网页签名（X-Argus/X-Gorgon，native .so 级）无法自算 → 走和抖音作品/合集（DYWorksCapture）
/// 完全同构的离屏 WebView 数据泵：让 TikTok 网页自己发签名请求，我们 hook 截获 `/api/recommend/item_list`
/// 响应、JS 端预解析成 slim、drain 抽回 Swift、scroll 触发页面自己翻页（不自拼 URL，避免风控软拒）。
///
/// 铁律边界说明：铁律禁的是「WebView 作为 UI」——本类 WebView **从不进可见 UI**（alpha 0.01、
/// 不可交互、insertSubview 到 window 最底层），仅作为 TikTok web 的 JS 执行 + 签名引擎，
/// 截获现成响应体。性质与已批准的 DYWebViewBootstrap / DYWorksCapture 数据泵一致，零界面。
///
/// 实现（照抄 DYWorksCapture，换 hookJS 与端点）：
/// tvOS 无公开 WebKit（v160 CI 实锤）→ DYWebViewShim.m dlopen 私有 WebKit + objc_msgSend 建 WKWebView，
/// `DYCreateWebViewWithInject` 已封装 v165 config 时序坑（先配 config+addUserScript 再 initWithFrame）。
/// hook 在 document-start 注入（page JS 跑之前装拦截器，零漏），1s 轮询 drainJS splice 抽干 window.__ttCap。
final class DYTiktokCapture: NSObject {
    static let shared = DYTiktokCapture()

    /// TikTok web 桌面 UA（泵 WebView + 播放请求头共用；TikTok CDN 直链需配对 UA）。
    static let tiktokUA = "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"

    /// 一条 TikTok 推荐视频（JS 端 slim 预解析结果，字段名已防御性兜底）。
    struct TiktokItem {
        var id: String = ""
        var desc: String = ""
        var playUrl: String = ""      // 视频 CDN 直链（recommend 响应 video.playAddr）
        var cover: String = ""
        var duration: Int = 0         // 秒
        var createTime: Int = 0       // unix 秒
        var nickname: String = ""
        var avatar: String = ""
        var uniqueId: String = ""
        var digg: Int = 0
        var comment: Int = 0
        var share: Int = 0
        var collect: Int = 0
    }

    /// 截获到一批 item（主线程回调）。DYFeedClient 注册 → 转 DYVideoInfo/URL → PlaybackEngine.merge。
    var onItems: (([TiktokItem]) -> Void)?

    private var webView: UIView?
    private var pollTimer: Timer?
    private var pollCount = 0
    private var totalCap = 0
    private var lastActivityAt = Date()
    private var seenIds: Set<String> = []   // 按 id 去重（FYP 相邻页有重叠）
    private var rawLogged = false           // 首版只 log 一次原始 schema 供核对

    // MARK: - 会话

    /// 确保离屏 WebView 会话在跑（首次创建加载 FYP；已存在则复用）。
    func ensureSession() {
        if webView != nil { return }
        guard let wv = DYCreateWebViewWithInject(CGRect(x: 0, y: 0, width: 1920, height: 1080), Self.tiktokUA, Self.hookJS) as? UIView else {
            DYLog.shared.event("TIKTOK FAIL: 注入式 WKWebView 创建失败（dlopen WebKit）")
            return
        }
        webView = wv
        if let win = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first {
            wv.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            wv.alpha = 0.01
            wv.isUserInteractionEnabled = false
            win.insertSubview(wv, at: 0)
        }
        pollCount = 0
        totalCap = 0
        lastActivityAt = Date()
        DYLog.shared.log("TIKTOK boot → tiktok.com/foryou (invisible pump webview)")
        wv.perform(NSSelectorFromString("loadRequest:"), with: NSURLRequest(url: URL(string: "https://www.tiktok.com/foryou")!))
        startPolling()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.pollCount += 1
            self.drain(tag: "p\(self.pollCount)")
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    /// 拆会话（切走 TikTok 源时由 DYFeedClient 调，释放离屏 WebView 避免幽灵层常驻）。
    func teardown() {
        pollTimer?.invalidate(); pollTimer = nil
        if let wv = webView, wv.superview != nil { wv.removeFromSuperview() }
        webView = nil
        rawLogged = false
    }

    /// 翻页：滚动触发页面自己发下一批 recommend（页面自签名）。onNeedMore → fetchPage → 这里。
    func requestMore() {
        ensureSession()
        evalJS("(function(){try{window.scrollBy(0,1400);}catch(e){}return 'ok';})();", tag: "scroll") { _ in }
    }

    // MARK: - 轮询 drain

    private func drain(tag: String) {
        guard webView != nil else { return }
        // 空闲收摊（90s 无新响应）——避免幽灵层常驻；下次 ensureSession 重建
        if Date().timeIntervalSince(lastActivityAt) > 90 {
            DYLog.shared.log("TIKTOK idle teardown (90s) total=\(totalCap)")
            teardown()
            return
        }
        evalJS(Self.drainJS, tag: tag) { [weak self] result in
            guard let self else { return }
            guard let json = result as? String, let data = json.data(using: .utf8),
                  let diag = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            let hooked = diag["hooked"] as? Bool ?? false
            // 首版 schema 透视：log 一次原始 item JSON 供核对字段名（仅一次）
            if let raw = diag["raw"] as? String, !raw.isEmpty, !self.rawLogged {
                self.rawLogged = true
                DYLog.shared.log("TIKTOK raw-item-schema \(raw.prefix(1200))")
            }
            let cap = diag["cap"] as? [[String: Any]] ?? []
            guard !cap.isEmpty else { return }
            self.lastActivityAt = Date()
            var items: [TiktokItem] = []
            for entry in cap {
                guard let b = entry["b"] as? String, let bdata = b.data(using: .utf8),
                      let obj = (try? JSONSerialization.jsonObject(with: bdata)) as? [String: Any],
                      let list = obj["items"] as? [[String: Any]] else { continue }
                for raw in list { if let it = self.parseSlim(raw), !it.playUrl.isEmpty, self.seenIds.insert(it.id).inserted { items.append(it) } }
            }
            if !items.isEmpty {
                self.totalCap += items.count
                DYLog.shared.log("TIKTOK drain[\(tag)] got=\(items.count) total=\(self.totalCap) hooked=\(hooked)")
                DispatchQueue.main.async { self.onItems?(items) }
            }
        }
    }

    /// JS slim → TiktokItem（防御性：字段缺失不致命，只要求 id+playUrl）
    private func parseSlim(_ d: [String: Any]) -> TiktokItem? {
        var it = TiktokItem()
        it.id = d["id"] as? String ?? ""
        it.desc = d["desc"] as? String ?? ""
        it.playUrl = d["u"] as? String ?? ""
        it.cover = d["cov"] as? String ?? ""
        it.duration = d["dur"] as? Int ?? 0
        it.createTime = d["ct"] as? Int ?? 0
        it.nickname = d["nick"] as? String ?? ""
        it.avatar = d["av"] as? String ?? ""
        it.uniqueId = d["uniq"] as? String ?? ""
        it.digg = d["dg"] as? Int ?? 0
        it.comment = d["cm"] as? Int ?? 0
        it.share = d["sh"] as? Int ?? 0
        it.collect = d["cl"] as? Int ?? 0
        guard !it.id.isEmpty, !it.playUrl.isEmpty else { return nil }
        return it
    }

    // MARK: - JS

    private func evalJS(_ js: String, tag: String, done: ((Any?) -> Void)? = nil) {
        guard let wv = webView else { return }
        let handler: @convention(block) (NSObject?, NSObject?) -> Void = { result, error in
            if let error = error as? NSError {
                DYLog.shared.log("TIKTOK[\(tag)] js err: \(error.localizedDescription)")
            }
            done?(result)
        }
        let block = unsafeBitCast(handler, to: AnyObject.self)
        wv.perform(NSSelectorFromString("evaluateJavaScript:completionHandler:"), with: js, with: block)
    }

    /// 抽回 __ttCap + 原始 schema 透视
    private static let drainJS = """
    (function(){
      var cap=[]; try{ cap=window.__ttCap.splice(0); }catch(e){}
      var raw=''; try{ raw=window.__ttRaw||''; if(raw) window.__ttRaw=''; }catch(e){}
      var diag={hooked:false,n:cap.length,cap:cap,raw:raw,rs:'',href:''};
      try{ diag.hooked=!!window.__ttHooked; }catch(e){}
      try{ diag.rs=document.readyState; }catch(e){}
      try{ diag.href=String(location.href).slice(0,80); }catch(e){}
      return JSON.stringify(diag);
    })();
    """

    /// document-start 注入的拦截器：命中 /api/recommend/item_list 的响应体在 JS 端预解析成 slim 存 window.__ttCap。
    /// 首个响应的原始 item JSON 存 window.__ttRaw（drain 取回 log 一次，供核对 TikTok web schema 字段名）。
    private static let hookJS = """
    (function(){
      if(window.__ttHooked) return; window.__ttHooked=true; window.__ttCap=[]; window.__ttRaw='';
      function grab(url, body){
        try{
          if(String(url).indexOf('recommend/item_list')<0) return;
          var j=null; try{ j=JSON.parse(body); }catch(e){}
          if(!j){ return; }
          var list = j.itemList || j.aweme_list || [];
          if(!list || !list.length){
            if(!window.__ttRaw){ try{ window.__ttRaw=JSON.stringify(j).slice(0,1500); }catch(e){} }
            return;
          }
          var slim=[];
          for(var i=0;i<list.length;i++){
            var a=list[i]||{}; var v=a.video||{};
            var pu = v.playAddr || v.play_addr || '';
            if(!pu && v.play_addr && v.play_addr.url_list) pu = v.play_addr.url_list[0]||'';
            if(!pu) pu = v.downloadAddr || v.download_addr || '';
            var cov = v.cover || v.originCover || '';
            if(cov && typeof cov!=='string') cov = (cov.url_list&&cov.url_list[0])||'';
            var au = a.author||{};
            var st = a.stats || a.statistics || {};
            slim.push({id:String(a.id||a.aweme_id||''), desc:String(a.desc||''), u:String(pu||''), cov:String(cov||''),
              dur:v.duration||0, ct:a.createTime||a.create_time||0,
              nick:au.nickname||'', uniq:au.uniqueId||'', av:au.avatarLarger||au.avatarMedium||'',
              dg:st.diggCount||0, cm:st.commentCount||0, sh:st.shareCount||0, cl:st.collectCount||0});
          }
          if(!window.__ttRaw){ try{ window.__ttRaw=JSON.stringify(list[0]).slice(0,1800); }catch(e){} }
          if(slim.length) window.__ttCap.push({ b: JSON.stringify({items:slim}) });
        }catch(e){}
      }
      var xo=XMLHttpRequest.prototype.open, xs=XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open=function(m,u){ this.__u=u; return xo.apply(this,arguments); };
      XMLHttpRequest.prototype.send=function(){ var x=this; this.__u=String(this.__u||'');
        this.addEventListener('readystatechange',function(){ if(x.readyState===4){ try{ var t=x.responseType; if(!t||t==='text'||t==='json'){ grab(x.__u,(t==='json')?x.response:x.responseText); } }catch(e){} } });
        return xs.apply(this,arguments); };
      var of=window.fetch;
      if(of){ window.fetch=function(){ var a=arguments,u=(a[0]&&a[0].url)||a[0]; u=String(u);
        return of.apply(this,arguments).then(function(r){ try{ var c=r.clone(); c.text().then(function(t){ grab(u,t); }).catch(function(){}); }catch(e){} return r; }); }; }
    })();
    """
}
