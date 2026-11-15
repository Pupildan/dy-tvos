import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v164"
    static let changes = "v164: 修v163 WebView截获零捕获根因——改用WKUserContentController document-start注入hook(DYCreateWebViewWithInject),page JS跑之前装好拦截器(v163用evaluateJavaScript事后注入漏首屏XHR);拦截器扩到aweme/post+series+mix合集端点;加诊断透视(readyState/href/hooked/xhrTotal/cap数)定位页面加载;离屏数据泵非UI"
}
