// DYWebViewShim.m — Objective-C shim exposing private-WebKit calls that need
// struct params (CGRect) or objc_msgSend / blocks / private classes, all of
// which are unavailable from Swift. Swift reaches these via the bridging header.

#import "DYWebViewShim.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>

// ---- latest hook message storage (JS -> ObjC -> Swift poll) ----
static NSString * _Nullable _dyLastHookMessage = nil;

@interface DYHookBridge : NSObject
@end
@implementation DYHookBridge
// WKWebView calls this dynamically; no private protocol header needed.
- (void)userContentController:(id)ucc didReceiveScriptMessage:(id)msg
{
    @try {
        id body = [msg valueForKey:@"body"];
        if ([body isKindOfClass:[NSString class]]) {
            _dyLastHookMessage = (NSString *)body;
        } else {
            _dyLastHookMessage = [body description];
        }
    } @catch (NSException *e) {
        _dyLastHookMessage = [NSString stringWithFormat:@"ERR: %@", e.reason];
    }
}
@end

@implementation DYWebViewShim
@end

id DYCreateWebViewWithFrame(CGRect frame, NSString * __nullable userAgent)
{
    if (!dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_LAZY)) return nil;
    Class WKWebViewCls = NSClassFromString(@"WKWebView");
    Class ConfigCls = NSClassFromString(@"WKWebViewConfiguration");
    if (!WKWebViewCls || !ConfigCls) return nil;

    id config = [[ConfigCls alloc] init];
    if (userAgent && [config respondsToSelector:@selector(setCustomUserAgent:)]) {
        [config setValue:userAgent forKey:@"customUserAgent"];
    }

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

static NSString * const DYFetchHookJS =
@"(function(){"
@" if(window.__dyyInstalled) return; window.__dyyInstalled=true;"
@" window.__dyyLog=[];"
@" function post(s){ try{ window.webkit.messageHandlers.dyyHook.postMessage(s);}catch(e){} }"
@" function looksVideo(u){ return /\\.mp4|\\.m3u8|douyinvod|\\/play\\/|video_id=|playAddr|play_addr/i.test(u); }"
@" function scan(txt, srcUrl){"
@"   if(typeof txt!=='string'||txt.length<10) return;"
@"   var m,re=/https?:[a-zA-Z0-9.\\-]+(?:\\/[^\"'\\\\\\s]*)?(?:\\.mp4|\\.m3u8)[a-zA-Z0-9.\\-]*/g;"
@"   while((m=re.exec(txt))!==null){"
@"     var u=m[0].replace(/\\\\u002F/g,'/').replace(/\\\\/g,'/');"
@"     if(looksVideo(u)){ var line='['+(srcUrl||'')+'] '+u; window.__dyyLog.push(line); post(line); }"
@"   }"
@" }"
@" var of=window.fetch;"
@" if(of){ window.fetch=function(){ var args=arguments; var u=(args[0]&&(typeof args[0]==='string'?args[0]:(args[0].url||'')))||'';"
@"   var p=of.apply(this,args);"
@"   try{ p.then(function(res){ try{ var cl=res.clone(); cl.text().then(function(t){ scan(t,u); }).catch(function(){}); }catch(e){} }).catch(function(){}); }catch(e){}"
@"   return p; }; }"
@" var oo=XMLHttpRequest.prototype.open, os=XMLHttpRequest.prototype.send;"
@" XMLHttpRequest.prototype.open=function(m,u){ this.__u=u; return oo.apply(this,arguments); };"
@" XMLHttpRequest.prototype.send=function(){ var s=this;"
@"   this.addEventListener('readystatechange',function(){ if(s.readyState===4){ try{ scan(s.responseText, s.__u);}catch(e){} } });"
@"   return os.apply(this,arguments); };"
@" post('HOOK_INSTALLED');"
@"})();";

void DYInstallFetchHook(id webView)
{
    if (!webView) return;
    @try {
        id config = [webView valueForKey:@"configuration"];
        id ucc = [config valueForKey:@"userContentController"];
        if (!ucc) return;

        Class UserScriptCls = NSClassFromString(@"WKUserScript");
        if (UserScriptCls) {
            id script = [[UserScriptCls alloc] initWithSource:DYFetchHookJS
                                               injectionTime:0 // WKUserScriptInjectionTimeAtDocumentStart
                                            forMainFrameOnly:YES];
            if ([ucc respondsToSelector:@selector(addUserScript:)]) {
                [ucc performSelector:@selector(addUserScript:) withObject:script];
            }
        }
        if ([ucc respondsToSelector:@selector(addScriptMessageHandler:name:)]) {
            [ucc addScriptMessageHandler:[[DYHookBridge alloc] init] name:@"dyyHook"];
        }
    } @catch (NSException *e) {
        _dyLastHookMessage = [NSString stringWithFormat:@"INSTALL_ERR: %@", e.reason];
    }
}

NSString * _Nullable DYLastHookMessage(void)
{
    return _dyLastHookMessage;
}

void DYClearHookMessage(void)
{
    _dyLastHookMessage = nil;
}
