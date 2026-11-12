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
@" var reqSeen={}, reqBatch=[], videoSeen={}, videoBatch=[];"
@" function flush(){"
@"   if(reqBatch.length){ post('REQS\\n'+reqBatch.join('\\n')); reqBatch=[]; }"
@"   if(videoBatch.length){ post('VIDEOS\\n'+videoBatch.join('\\n')); videoBatch=[]; }"
@" }"
@" function addReq(u){ if(!u) return; u=String(u); if(u.length>200)u=u.slice(0,200); if(reqSeen[u])return; reqSeen[u]=1; reqBatch.push(u); }"
@" function addVideo(u,src){ var line=(src||'')+' >> '+u; if(videoSeen[line])return; videoSeen[line]=1; videoBatch.push(line); }"
@" function post(s){ try{ window.webkit.messageHandlers.dyyHook.postMessage(s);}catch(e){} }"
@" function looksVideo(u){ return /\\.mp4|\\.m3u8|douyinvod|\\/play\\/|video_id=|playAddr|play_addr/i.test(u); }"
@" function scan(txt, srcUrl){"
@"   if(typeof txt!=='string'||txt.length<10) return;"
@"   if(/module\\/feed|aweme\\/v[12]\\/web\\/feed/i.test(srcUrl||'')){"
@"     try{ var j=JSON.parse(txt); var list=j.aweme_list||j.awemes||[]; var n=0;"
@"       for(var i=0;i<list.length;i++){ var a=list[i]; if(!a) continue;"
@"         var v=a.video||{}; var pa=v.play_addr||v.download_addr||{}; var ul=pa.url_list||[];"
@"         for(var k=0;k<ul.length;k++){ var u=ul[k]; if(typeof u!=='string') continue;"
@"           if(u.indexOf('//')===0) u='https:'+u;"
@"           addVideo(u, 'aweme_'+(a.aweme_id||i)); n++; }"
@"       }"
@"       post('FEEDPARSED videos='+n+' awemes='+list.length);"
@"     }catch(e){ post('FEEDPARSE_ERR '+e); }"
@"     return;"
@"   }"
@"   var m,re=/https?:[a-zA-Z0-9.\\-]+(?:\\/[^\"'\\\\\\s]*)?(?:\\.mp4|\\.m3u8)[a-zA-Z0-9.\\-]*/g;"
@"   while((m=re.exec(txt))!==null){"
@"     var u=m[0].replace(/\\\\u002F/g,'/').replace(/\\\\/g,'/');"
@"     if(looksVideo(u)) addVideo(u, srcUrl);"
@"   }"
@" }"
@" var of=window.fetch;"
@" if(of){ window.fetch=function(){ var args=arguments; var u=(args[0]&&(typeof args[0]==='string'?args[0]:(args[0].url||'')))||'';"
@"   addReq(u);"
@"   var p=of.apply(this,args);"
@"   try{ p.then(function(res){ try{ var cl=res.clone(); cl.text().then(function(t){ scan(t,u); }).catch(function(){}); }catch(e){} }).catch(function(){}); }catch(e){}"
@"   return p; }; }"
@" var oo=XMLHttpRequest.prototype.open, os=XMLHttpRequest.prototype.send;"
@" XMLHttpRequest.prototype.open=function(m,u){ this.__u=u; addReq(u); return oo.apply(this,arguments); };"
@" XMLHttpRequest.prototype.send=function(){ var s=this;"
@"   this.addEventListener('readystatechange',function(){ if(s.readyState===4){ try{ scan(s.responseText, s.__u);}catch(e){} } });"
@"   return os.apply(this,arguments); };"
@" setInterval(flush, 2000);"
@" setInterval(function(){ try{ window.scrollTo(0, document.body.scrollHeight); }catch(e){} }, 2500);"
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
            id raw = ((id(*)(id, SEL))objc_msgSend)((id)UserScriptCls, @selector(alloc));
            // initWithSource:injectionTime:forMainFrameOnly: (private selector; objc_msgSend cast)
            id script = ((id(*)(id, SEL, NSString*, NSUInteger, BOOL))objc_msgSend)
                        (raw, @selector(initWithSource:injectionTime:forMainFrameOnly:),
                         DYFetchHookJS, 0 /*AtDocumentStart*/, YES);
            if (script && [ucc respondsToSelector:@selector(addUserScript:)]) {
                [ucc performSelector:@selector(addUserScript:) withObject:script];
            }
        }
        if ([ucc respondsToSelector:@selector(addScriptMessageHandler:name:)]) {
            id handler = [[DYHookBridge alloc] init];
            ((void(*)(id, SEL, id, NSString*))objc_msgSend)
                (ucc, @selector(addScriptMessageHandler:name:), handler, @"dyyHook");
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
