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
    if ([wv respondsToSelector:@selector(setConfiguration:)]) {
        [wv setValue:config forKey:@"configuration"];
    }
    return wv;
}
