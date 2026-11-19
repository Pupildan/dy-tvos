// DYWebViewShim.h — exposed to Swift via the bridging header.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Allocate + init a private WKWebView with a CGRect frame and desktop UA.
/// Returns nil if the private WebKit.framework / WKWebView is unavailable.
/// All struct-parameter ObjC messaging lives here (ObjC may call objc_msgSend freely).
FOUNDATION_EXPORT id _Nullable DYCreateWebViewWithFrame(CGRect frame, NSString * _Nullable userAgent);

/// v164：带 document-start 注入的 WKWebView（截获页面自发的 XHR/fetch 响应）。
/// injectScript 在页面任何 JS 之前执行（WKUserContentController addUserScript，document start）。
/// 用于 DYWorksCapture：让抖音作者页自己算 168 签名发 aweme/post，我们只拦现成响应体。
FOUNDATION_EXPORT id _Nullable DYCreateWebViewWithInject(CGRect frame, NSString * _Nullable userAgent, NSString * _Nullable injectScript);

/// v228：收割 WKWebView 默认数据存储的全量 cookie（含 HttpOnly），返回 "k=v; k=v" 串。
/// TikTok CDN playAddr 绑定浏览器会话（开发机实测：页面内 206/裸请求 403）→ 播放头必须带 WebView cookie。
/// ⚠️ 内部信号量等异步 getAllCookies（≤3s），调用方放后台队列。
FOUNDATION_EXPORT NSString * _Nullable DYWebKitCookieHeader(void);

NS_ASSUME_NONNULL_END
