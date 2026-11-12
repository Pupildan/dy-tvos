import Foundation
import ObjectiveC.runtime

/// A 路线可行性探针：tvOS SDK 无公开 WKWebView，尝试运行时加载私有 WebKit。
/// 编译期不依赖任何 WebKit 符号，CI 可安全编译；可行性只能真机验证。
/// 焦点意图：本文件无 UI，不参与焦点。
enum WebKitProbe {
    struct Result {
        let dylibLoaded: Bool
        let dylibPath: String?
        let wkWebViewClass: String?
        let instanceCreated: Bool
        let error: String?

        var summary: String {
            var lines: [String] = []
            lines.append("dlopen WebKit: \(dylibLoaded ? "OK" : "FAIL")")
            if let p = dylibPath { lines.append("  path: \(p)") }
            lines.append("WKWebView class: \(wkWebViewClass ?? "nil")")
            lines.append("instance: \(instanceCreated ? "OK" : "FAIL")")
            if let e = error { lines.append("error: \(e)") }
            return lines.joined(separator: "\n")
        }
    }

    static func run() -> Result {
        let path = "/System/Library/Frameworks/WebKit.framework/WebKit"
        guard dlopen(path, RTLD_LAZY) != nil else {
            return Result(dylibLoaded: false, dylibPath: nil, wkWebViewClass: nil,
                          instanceCreated: false,
                          error: "dlopen failed: \(String(cString: dlerror()))")
        }
        guard let cls: AnyClass = NSClassFromString("WKWebView") else {
            return Result(dylibLoaded: true, dylibPath: path, wkWebViewClass: nil,
                          instanceCreated: false, error: "WKWebView class not found")
        }
        // AnyClass -> NSObject.Type 需强转 as!（条件 as? 不编译）
        let nsCls = cls as! NSObject.Type
        var instanceOK = false
        var err: String? = nil
        let obj = nsCls.alloc()
        let sel = NSSelectorFromString("initWithFrame:configuration:")
        if obj.responds(to: sel) {
            if let configCls: AnyClass = NSClassFromString("WKWebViewConfiguration") {
                let config = (configCls as! NSObject.Type).alloc()
                config.perform(NSSelectorFromString("init"))
                let result = obj.perform(sel, with: NSValue(cgRect: .zero), with: config)
                instanceOK = (result != nil)
            } else {
                err = "WKWebViewConfiguration class not found"
            }
        } else {
            err = "initWithFrame:configuration: not found"
        }
        return Result(dylibLoaded: true, dylibPath: path,
                      wkWebViewClass: NSStringFromClass(cls),
                      instanceCreated: instanceOK, error: err)
    }
}
