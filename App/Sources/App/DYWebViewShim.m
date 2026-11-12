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
        NSString *s = [body isKindOfClass:[NSString class]] ? (NSString *)body : [body description];
        if ([s hasPrefix:@"COOKIE\n"]) {
            DYSetPageCookie([s substringFromIndex:7]); // 持久存 cookie 供 AVPlayer 头
        } else {
            _dyLastHookMessage = s;
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
@" try{ window.webkit.messageHandlers.dyyHook.postMessage('HOOK_START'); }catch(e){}"
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
@" window.__dyyRI=1;"
@" window.__dyyMore=function(){"
@"   try{ window.__dyyRI++;"
@"     var u='https://www.douyin.com/aweme/v2/web/module/feed/?device_platform=webapp&aid=6383&channel=channel_pc_web&module_id=3003101&count=20&refresh_index='+window.__dyyRI+'&refer_id=&refer_type=10&pc_client_type=1&pc_libra_divert=Mac&support_h265=0&support_dash=0&cpu_core_num=4&version_code=170400&video_type_select=1&filter_warn=0&need_fix_st=0&web_page_type=0&os=mac&pull_type=2&is_follow_live=0&poi_data=0&whale_cut_token=&globalId=tobid&msToken=&a_bogus=&X-Bogus=';"
@"     if(window.__dyySeen['M'+window.__dyyRI])return; window.__dyySeen['M'+window.__dyyRI]=1;"
@"     fetch(u,{credentials:'include'}).then(function(r){return r.text();}).then(function(t){ scan(t,u); flush(); }).catch(function(e){ post('MORE_ERR '+e); });"
@"   }catch(e){ post('MORE_ERR '+e); }"
@" };"
@" function dyyFindScroller(){"
@"   var best=null,bestH=0;"
@"   try{ var all=document.querySelectorAll('div,main,section');"
@"     for(var i=0;i<all.length;i++){ var el=all[i];"
@"       try{ var cs=getComputedStyle(el); var oy=cs.overflowY;"
@"         if((oy==='scroll'||oy==='auto') && el.scrollHeight>el.clientHeight+200 && el.clientHeight>200){"
@"           if(el.scrollHeight>bestH){ best=el; bestH=el.scrollHeight; }"
@"         }"
@"       }catch(e){}"
@"     }"
@"   }catch(e){}"
@"   return best;"
@" }"
@" function dyyScrollOnce(){"
@"   try{"
@"     var el=dyyFindScroller();"
@"     var host=el||document.body||document.documentElement;"
@"     var h=el?el.scrollHeight:(document.body?document.body.scrollHeight:99999);"
@"     // 1) hardware WheelEvent mimics real user scrolling (deltaY 800)"
@"     try{ host.dispatchEvent(new WheelEvent('wheel',{bubbles:true,cancelable:true,deltaY:800,deltaMode:0})); }catch(e){}"
@"     // 2) TouchEvent sequence start-move-end"
@"     try{ host.dispatchEvent(new TouchEvent('touchstart',{bubbles:true,cancelable:true}));"
@"          host.dispatchEvent(new TouchEvent('touchmove',{bubbles:true,cancelable:true}));"
@"          host.dispatchEvent(new TouchEvent('touchend',{bubbles:true,cancelable:true})); }catch(e){}"
@"     // 3) real scroll plus scroll events on both window and container"
@"     try{ if(el){ el.scrollTop=h; } window.scrollTo(0,document.body?document.body.scrollHeight:99999);"
@"          host.dispatchEvent(new Event('scroll',{bubbles:true})); window.dispatchEvent(new Event('scroll')); }catch(e){}"
@"     // 4) force bottom sentinel into viewport to trigger IntersectionObserver next page"
@"     try{ if(el&&el.lastElementChild) el.lastElementChild.scrollIntoView({block:'end'});"
@"          var sents=document.querySelectorAll('[data-sentinel],[class*=sentinel],[class*=loader],[class*=load-more],[class*=loading]');"
@"          for(var i=0;i<sents.length&&i<3;i++){ sents[i].scrollIntoView({block:'center'}); } }catch(e){}"
@"   }catch(e){}"
@" }"
@" function dyyMuteVideos(){"
@"   try{ var vs=document.querySelectorAll('video');"
@"     for(var i=0;i<vs.length;i++){ try{ vs[i].muted=true; vs[i].pause(); }catch(e){} }"
@"   }catch(e){}"
@" }"
@" window.__dyyScroll = dyyScrollOnce;"
@" window.__dyyMore = window.__dyyMore;"
@" setInterval(dyyMuteVideos, 1500);"
@" setInterval(dyyScrollOnce, 2500);"
@" setInterval(function(){ window.__dyyMore(); }, 7000);"
@" post('HOOK_INSTALLED');"
@" try{ post('COOKIE\\n'+document.cookie); }catch(e){}"
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

// ---- captured page cookie (for AVPlayer Referer/Cookie headers) ----
static NSString * _Nullable _dyPageCookie = nil;

void DYSetPageCookie(NSString *cookie)
{
    _dyPageCookie = cookie;
}

NSString * _Nullable DYGetPageCookie(void)
{
    return _dyPageCookie;
}

void DYEvalJS(id webView, NSString *js)
{
    if (!webView || !js) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        // evaluateJavaScript:completionHandler: —— 用 @selector 避免 C 字符串需 @ 前缀的编译错误
        void (*msgSend)(id, SEL, NSString *, void (^)(id, NSError *)) =
            (void (*)(id, SEL, NSString *, void (^)(id, NSError *)))objc_msgSend;
        msgSend(webView, @selector(evaluateJavaScript:completionHandler:), js, ^(id r, NSError *e) {});
    });
}
