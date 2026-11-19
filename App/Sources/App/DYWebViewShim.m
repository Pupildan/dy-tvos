// DYWebViewShim.m — Objective-C shim exposing private-WebKit calls that need
// struct params (CGRect) or objc_msgSend, which are unavailable from Swift.
// Swift reaches these via the bridging header. ObjC may call objc_msgSend freely.

#import "DYWebViewShim.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>

id DYCreateWebViewWithFrame(CGRect frame, NSString * __nullable userAgent)
{
    // Load private WebKit.framework at runtime
    if (!dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_LAZY)) return nil;
    Class WKWebViewCls = NSClassFromString(@"WKWebView");
    Class ConfigCls = NSClassFromString(@"WKWebViewConfiguration");
    if (!WKWebViewCls || !ConfigCls) return nil;

    id config = [[ConfigCls alloc] init];
    if (userAgent && [config respondsToSelector:@selector(setCustomUserAgent:)]) {
        [config setValue:userAgent forKey:@"customUserAgent"];
    }

    // initWithFrame: carries a CGRect struct -> must go through objc_msgSend (C convention)
    SEL frameSel = @selector(initWithFrame:);
    id raw = ((id(*)(id, SEL))objc_msgSend)((id)WKWebViewCls, @selector(alloc));
    if (![raw respondsToSelector:frameSel]) return nil;
    id wv = ((id(*)(id, SEL, CGRect))objc_msgSend)(raw, frameSel, frame);
    if (!wv) return nil;

    if ([wv respondsToSelector:@selector(setConfiguration:)]) {
        [wv setValue:config forKey:@"configuration"];
    }
    return wv;
}

// v163/v164：带 document-start 注入的创建（截获页面自己发的 XHR/fetch 响应）。
// 关键：hook 必须在页面任何 JS 之前装好——用 WKUserContentController addUserScript
// (injectionTime = document start)。evaluateJavaScript 事后注入会漏首屏 XHR（v163 零捕获根因）。
// injectScript 非空时，经 WKUserContentController 加 document-start 用户脚本。
id DYCreateWebViewWithInject(CGRect frame, NSString * __nullable userAgent, NSString * __nullable injectScript)
{
    if (!dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_LAZY)) return nil;
    Class WKWebViewCls = NSClassFromString(@"WKWebView");
    Class ConfigCls = NSClassFromString(@"WKWebViewConfiguration");
    Class UserScriptCls = NSClassFromString(@"WKUserScript");
    Class ContentCtlCls = NSClassFromString(@"WKUserContentController");
    if (!WKWebViewCls || !ConfigCls) return nil;

    id config = [[ConfigCls alloc] init];
    if (userAgent && [config respondsToSelector:@selector(setCustomUserAgent:)]) {
        [config setValue:userAgent forKey:@"customUserAgent"];
    }

    // document-start 注入：page JS 跑之前装拦截器（零漏）
    // ⚠️ 必须在 initWithFrame: 之前配好 config——WKWebView 在 initWithFrame 时拷贝 configuration，
    //    之后再 setConfiguration: 换不掉（v164 首版 hooked=0 根因：addUserScript 加到了没被采用的 config 上）。
    if (injectScript && UserScriptCls && ContentCtlCls && [config respondsToSelector:@selector(userContentController)]) {
        id contentCtl = [config valueForKey:@"userContentController"];
        id script = ((id(*)(id, SEL))objc_msgSend)(UserScriptCls, @selector(alloc));
        SEL initSel = @selector(initWithSource:injectionTime:forMainFrameOnly:);
        if (script && [script respondsToSelector:initSel]) {
            // WKUserScriptInjectionTimeAtDocumentStart = 0；forMainFrameOnly = YES
            id usr = ((id(*)(id, SEL, NSString*, NSInteger, BOOL))objc_msgSend)(script, initSel, injectScript, 0, YES);
            if (usr && [contentCtl respondsToSelector:@selector(addUserScript:)]) {
                [contentCtl performSelector:@selector(addUserScript:) withObject:usr];
            }
        }
    }

    SEL frameSel = @selector(initWithFrame:);
    id raw = ((id(*)(id, SEL))objc_msgSend)(WKWebViewCls, @selector(alloc));
    if (![raw respondsToSelector:frameSel]) return nil;
    id wv = ((id(*)(id, SEL, CGRect))objc_msgSend)(raw, frameSel, frame);
    if (!wv) return nil;
    return wv;
}

// v228：收割 WKWebView 默认数据存储的全量 cookie（含 HttpOnly——document.cookie 永远不可见），
// 返回 "k=v; k=v" 串供 AVPlayer 播放请求头。
// 依据：TikTok CDN playAddr 直链绑定浏览器会话——开发机实测页面内 fetch=206 video/mp4，
// 脱离会话（裸 UA/+Referer/无 UA 三组）全部 403。和 HANDOVER §5.3⑤A 规划的 WKHTTPCookieStore
// 私有收割同款。getAllCookies: 是异步完成回调，内部信号量等完成（回调在 WKHTTPCookieStore
// 内部队列不占主队列；保险起见调用方放后台队列调）。
NSString * _Nullable DYWebKitCookieHeader(void)
{
    if (!dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_LAZY)) return nil;
    Class StoreCls = NSClassFromString(@"WKWebsiteDataStore");
    if (!StoreCls) return nil;
    SEL defaultSel = @selector(defaultDataStore);
    if (![StoreCls respondsToSelector:defaultSel]) return nil;
    id store = ((id(*)(id, SEL))objc_msgSend)(StoreCls, defaultSel);
    if (!store || ![store respondsToSelector:@selector(httpCookieStore)]) return nil;
    id ckStore = ((id(*)(id, SEL))objc_msgSend)(store, @selector(httpCookieStore));
    if (!ckStore || ![ckStore respondsToSelector:@selector(getAllCookies:)]) return nil;

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSMutableString *out = [NSMutableString string];
    void (^block)(NSArray *) = ^(NSArray *cookies) {
        for (NSHTTPCookie *c in cookies) {
            [out appendFormat:@"%@=%@; ", c.name, c.value];
        }
        dispatch_semaphore_signal(sem);
    };
    ((void(*)(id, SEL, id))objc_msgSend)(ckStore, @selector(getAllCookies:), block);
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
    if (out.length < 2) return nil;
    return [out substringWithRange:NSMakeRange(0, out.length - 2)];   // 去尾 "; "
}
