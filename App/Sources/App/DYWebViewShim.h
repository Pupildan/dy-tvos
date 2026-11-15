// DYWebViewShim.h — exposed to Swift via the bridging header.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// Allocate + init a private WKWebView with a CGRect frame and desktop UA.
/// Returns nil if the private WebKit.framework / WKWebView is unavailable.
/// All struct-parameter ObjC messaging lives here (ObjC may call objc_msgSend freely).
FOUNDATION_EXPORT id _Nullable DYCreateWebViewWithFrame(CGRect frame, NSString * _Nullable userAgent);

NS_ASSUME_NONNULL_END
