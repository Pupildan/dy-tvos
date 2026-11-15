import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v165"
    static let changes = "v165: 修v164 hooked=0根因——shim里setConfiguration:在initWithFrame:之后=WKWebView已拷贝config换不掉,addUserScript加到没被采用的config上;改为先配userContentController(hook)再建WKWebView;另加evaluateJavaScript补装hook兜底(drain查__dyHooked=0则rehook),双保险确保拦截器装上"
}
