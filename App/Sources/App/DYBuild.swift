import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v161"
    static let changes = "v161: WebView引导修复——v160用公开WebKit模块CI实锤tvOS无公开WebKit(unable to resolve WebKit);改回v2-v8真机验证过的私有方案:DYWebViewShim.m回归(dlopen私有WebKit.framework+objc_msgSend建WKWebView)+桥接头回归+引导改isLoading轮询+evaluateJavaScript收割document.cookie(挑战页JS种的s_v_web_id/__ac_signature/uifid)+失败2s重试6轮+20s兜底;确认键长按两倍速不变"
}
