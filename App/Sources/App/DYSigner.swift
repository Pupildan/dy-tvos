import Foundation
import JavaScriptCore

/// 本地 a_bogus 签名器：JavaScriptCore 运行 myDV 验证过的签名 JS。
/// 架构（对齐 myDV ABogusSigner/QuickJS）：
///   browser shim → abogus.js(XHR 捕获) → bdms.js(字节安全 SDK) → sign.js → abogus_dy.js
///   → initABogus() → getABogus(query, data, uri) 返回 JSON {ok, value}
/// 纯原生方案，替代隐藏 WebView 泵。JS 资产来自 myDV v2.3.45（GPL-3.0 个人学习用途，见 NOTICE.txt）。
/// 线程模型：JSContext 非线程安全，全部操作串行在 signer 队列。
final class DYSigner {
    static let shared = DYSigner()
    private let queue = DispatchQueue(label: "dy.signer")
    private var context: JSContext?
    private(set) var ready = false
    /// 签名运行时就绪回调（主队列触发；若已就绪则立即触发）。
    var onReady: (() -> Void)? {
        didSet { notifyIfReady() }
    }

    private init() {}

    /// 初始化签名运行时（幂等）。所有步骤结果写 DYLog，真机可诊断。
    func initialize() {
        queue.async { self._initialize() }
    }

    private func notifyIfReady() {
        guard ready else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onReady?()
        }
    }

    private func _initialize() {
        guard context == nil else { return }
        DYLog.shared.log("SIGNER init start")
        let ctx = JSContext()
        context = ctx
        guard let ctx else {
            DYLog.shared.log("SIGNER FAIL: JSContext nil")
            return
        }
        // 关键：不设自定义 exceptionHandler —— 有 handler 时 ctx.exception 恒为 nil，
        // load() 的异常检测会失效（v35 的静默失败根因之一）。用默认行为 + load() 检查。

        // 1) browser shim（必须最先；提供 window/navigator/document/XHR/fetch/crypto 等全套仿真）
        guard load(ctx, "dy_browser_shim", log: "shim") else { return }
        // 2) abogus.js（XHR 捕获钩子；必须先于 abogus_dy.js —— 后者内含 bdms）
        guard load(ctx, "abogus", log: "abogus") else { return }
        // 3) sign.js
        let signOK = load(ctx, "sign", log: "sign")
        // 4) abogus_dy.js = 自足主签名包（内含 bdms/initABogus/getABogus/get_ab，覆盖前面的定义）。
        //    注意：不加载独立 bdms.js —— 双 bdms 定义会覆盖 _v 状态致 init 冲突（v36 实测）。
        let dyOK = load(ctx, "abogus_dy", log: "abogus_dy")
        DYLog.shared.log("SIGNER extras sign=\(signOK) dy=\(dyOK)")

        // 5) bdms 存在性检查（对齐 myDV）
        let bdmsCheck = ctx.evaluateScript("(function(){ return (typeof window.bdms !== 'undefined' && typeof window.bdms.init === 'function') ? 'yes' : 'no'; })()")
        DYLog.shared.log("SIGNER bdms=\(bdmsCheck?.toString() ?? "nil")")

        // 6) initABogus()
        let initResult = ctx.evaluateScript("typeof initABogus === 'function' ? String(initABogus()) : 'no-fn'")
        DYLog.shared.log("SIGNER initABogus=\(initResult?.toString() ?? "nil")")

        // 7) 双函数检查（对齐 myDV：getABogus + get_ab 必须同时存在）
        let check = ctx.evaluateScript("(function(){ return (typeof getABogus === 'function' ? 'A' : '-') + (typeof get_ab === 'function' ? 'B' : '-'); })()")
        DYLog.shared.log("SIGNER fns=\(check?.toString() ?? "nil") (期望 AB)")

        // 8) 冒烟测试（对齐 myDV）
        let smoke = ctx.evaluateScript("(function(){ try { return getABogus('aid=6383&device_platform=webapp', ''); } catch(e) { return JSON.stringify({ok:false,error:String(e)}); } })()")
        // getABogus 返回的是 JSON 字符串（不是 JS 对象），必须先解析字符串再取字段。
        let raw = smoke?.toString() ?? ""
        DYLog.shared.log("SIGNER smoke=\(String(raw.prefix(140)))")
        if let d = raw.data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
           let ok = obj["ok"] as? Bool, ok,
           let value = obj["value"] as? String, !value.isEmpty {
            ready = true
            DYLog.shared.log("SIGNER READY a_bogus len=\(value.count)")
            notifyIfReady()
        } else {
            DYLog.shared.log("SIGNER NOT READY")
        }
    }

    private func load(_ ctx: JSContext, _ name: String, log: String) -> Bool {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let src = try? String(contentsOf: url, encoding: .utf8) else {
            DYLog.shared.log("SIGNER load \(log) FAIL (missing)")
            return false
        }
        ctx.evaluateScript(src)
        if let err = ctx.exception {
            DYLog.shared.log("SIGNER load \(log) exception: \(String(err.toString().prefix(140)))")
            ctx.exception = nil
            return false
        }
        DYLog.shared.log("SIGNER load \(log) ok")
        return true
    }

    /// 签名结果：a_bogus 值 + bdms 注入的安全头（如 x-secsdk-web-signature）。
    struct SignResult {
        let value: String
        let headers: [String: String]
    }

    /// 计算 a_bogus。query 不含 '?'；data=POST body 字符串（GET 传 ''）；uri=API 路径（可空）。
    /// 返回签名+安全头，或 nil（未就绪/签名失败）。串行队列内执行。
    func sign(query: String, data: String, uri: String) -> SignResult? {
        // JSContext 非线程安全：经队列同步执行
        var result: SignResult?
        queue.sync {
            guard ready, let ctx = context, let fn = ctx.objectForKeyedSubscript("getABogus") else {
                result = nil
                return
            }
            guard let out = fn.call(withArguments: [query, data, uri])?.toString() else {
                result = nil
                return
            }
            // 返回 JSON 字符串 {"ok":true,"value":"...","headers":{...}} 或 {"ok":false,"error":"..."}
            guard let d = out.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let ok = obj["ok"] as? Bool, ok,
                  let value = obj["value"] as? String, !value.isEmpty else {
                DYLog.shared.log("SIGNER sign fail: \(String(out.prefix(120)))")
                result = nil
                return
            }
            var headers: [String: String] = [:]
            if let hs = obj["headers"] as? [String: Any] {
                for (k, v) in hs { if let s = v as? String { headers[k] = s } }
            }
            result = SignResult(value: value, headers: headers)
        }
        return result
    }
}
