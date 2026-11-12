// DYWebViewShim.h — exposed to Swift via the bridging header.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Allocate + init a private WKWebView with a CGRect frame and desktop UA.
/// Returns nil if the private WebKit.framework / WKWebView is unavailable.
/// All struct-parameter ObjC messaging lives here (ObjC may call objc_msgSend freely).
FOUNDATION_EXPORT id _Nullable DYCreateWebViewWithFrame(CGRect frame, NSString * _Nullable userAgent);

/// Inject a documentStart fetch/XHR hook that captures video direct-links
/// (.mp4/.m3u8/douyinvod/play_addr) from Douyin feed API responses and forwards
/// each hit to the native side via the "dyyHook" script-message handler.
FOUNDATION_EXPORT void DYInstallFetchHook(id webView);

/// Latest message posted from the injected hook (one captured URL per post, or
/// a diagnostic line). Returns nil if nothing new since DYClearHookMessage.
FOUNDATION_EXPORT NSString * _Nullable DYLastHookMessage(void);

/// Clear the latest hook message (call after consuming, to detect the next).
FOUNDATION_EXPORT void DYClearHookMessage(void);

/// Evaluate a JS string on the page (main thread). Used by native to trigger
/// the page's own scroll / pagination (window.__dyyScroll / __dyyMore).
FOUNDATION_EXPORT void DYEvalJS(id webView, NSString *js);

/// Store the page cookie (captured by the hook) for AVPlayer Referer/Cookie headers.
FOUNDATION_EXPORT void DYSetPageCookie(NSString *cookie);

/// Latest captured page cookie (nil if none yet).
FOUNDATION_EXPORT NSString * _Nullable DYGetPageCookie(void);

NS_ASSUME_NONNULL_END
