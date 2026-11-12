// hook 功能模拟：Node 沙盒 + 浏览器仿真 + 模拟 feed 响应，验证整条 JS 管线
const fs = require('fs');
const vm = require('vm');

const code = fs.readFileSync('C:/Nbeetok/dy-tvos/_tmp/hook_from_binary.js', 'utf8');

// ---- 收集断言结果 ----
const posted = [];
const timers = [];
let PASS = 0, FAIL = 0;
function check(name, cond, detail) {
  if (cond) { PASS++; console.log('PASS  ' + name + (detail ? '  ' + detail : '')); }
  else { FAIL++; console.log('FAIL  ' + name + (detail ? '  ' + detail : '')); }
}

// ---- 浏览器仿真 ----
const sandbox = {};
const g = sandbox; // window === global
g.window = g;
g.self = g;
g.top = g;
g.parent = g;
g.frames = g;
g.navigator = { userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36', platform: 'Win32', language: 'zh-CN', cookieEnabled: true, onLine: true, hardwareConcurrency: 8, maxTouchPoints: 0, deviceMemory: 8, plugins: { length: 0 }, mimeTypes: { length: 0 }, webdriver: false };
g.screen = { width: 1920, height: 1080, availWidth: 1920, availHeight: 1040, colorDepth: 24, pixelDepth: 24 };
g.innerWidth = 1920; g.innerHeight = 1040; g.devicePixelRatio = 1;
let _cookie = 'ttwid=abc123; msToken=mocktoken123; sessionid=;';
g.document = {
  body: { clientWidth: 1920, clientHeight: 1040, scrollHeight: 8000, dispatchEvent: function(){}, lastElementChild: null },
  documentElement: { clientWidth: 1920, clientHeight: 1040 },
  title: '', domain: 'douyin.com', referrer: '', readyState: 'complete', hidden: false, visibilityState: 'visible',
  location: { href: 'https://www.douyin.com/', protocol: 'https:', host: 'www.douyin.com', hostname: 'www.douyin.com', pathname: '/', origin: 'https://www.douyin.com' },
  createElement: function(t){ return { tagName: String(t).toUpperCase(), style: {}, setAttribute(){}, getAttribute(){ return null; }, appendChild(){}, addEventListener(){}, getBoundingClientRect(){ return {top:0,left:0,bottom:0,right:0,width:0,height:0}; } }; },
  createTextNode: function(t){ return { nodeValue: t }; },
  getElementById(){ return null; }, getElementsByTagName(){ return []; }, getElementsByClassName(){ return []; },
  querySelector(){ return null; }, querySelectorAll(){ return []; },
  addEventListener(){}, removeEventListener(){},
  createEvent(){ return { initEvent(){}, preventDefault(){}, stopPropagation(){} }; }
};
Object.defineProperty(g.document, 'cookie', { get(){ return _cookie; }, set(v){ _cookie = v; } });
g.location = g.document.location;
g.XMLHttpRequest = function(){ this.readyState = 0; this.status = 0; this.responseText = ''; this.withCredentials = false; };
g.XMLHttpRequest.prototype.open = function(m,u){ this.__method = m; this.__url = u; this.readyState = 1; };
g.XMLHttpRequest.prototype.send = function(b){ this.__body = b || null; };
g.XMLHttpRequest.prototype.abort = function(){};
g.XMLHttpRequest.prototype.setRequestHeader = function(){};
g.XMLHttpRequest.prototype.getResponseHeader = function(){ return null; };
g.XMLHttpRequest.prototype.getAllResponseHeaders = function(){ return ''; };
g.XMLHttpRequest.prototype.addEventListener = function(){};
g.XMLHttpRequest.prototype.removeEventListener = function(){};
// 原始 mock fetch：返回可 clone 的模拟响应（由测试注入内容）
let mockResponseText = '';
g.fetch = function(input, init){ return Promise.resolve({ ok: true, status: 200, text(){ return Promise.resolve(mockResponseText); }, clone(){ return { text(){ return Promise.resolve(mockResponseText); } }; }, json(){ return Promise.resolve(JSON.parse(mockResponseText)); } }); };
g.setTimeout = function(fn, ms){ timers.push(['timeout', fn, ms]); return timers.length; };
g.setInterval = function(fn, ms){ timers.push(['interval', fn, ms]); return timers.length; };
g.clearTimeout = function(){}; g.clearInterval = function(){};
g.requestAnimationFrame = function(fn){ return 0; }; g.cancelAnimationFrame = function(){};
g.localStorage = { getItem(){ return null; }, setItem(){}, removeItem(){}, clear(){}, get length(){ return 0; } };
g.sessionStorage = g.localStorage;
g.crypto = { getRandomValues(a){ for(let i=0;i<a.length;i++) a[i]=Math.floor(Math.random()*256); return a; }, subtle: { digest(){ return Promise.resolve(new ArrayBuffer(32)); } } };
g.performance = { now(){ return Date.now(); } };
g.history = { pushState(){}, replaceState(){}, go(){}, back(){}, forward(){}, length: 0 };
g.getComputedStyle = function(){ return new Proxy({}, { get(){ return ''; } }); };
g.matchMedia = function(){ return { matches: false, addListener(){}, removeListener(){}, addEventListener(){}, removeEventListener(){} }; };
g.Image = function(){ return {}; };
g.MutationObserver = function(){ return { observe(){}, disconnect(){}, takeRecords(){ return []; } }; };
g.IntersectionObserver = function(){ return { observe(){}, disconnect(){} }; };
g.ResizeObserver = function(){ return { observe(){}, disconnect(){} }; };
g.Worker = function(){ return { postMessage(){}, terminate(){} }; };
g.Event = function(type){ this.type = type; };
g.CustomEvent = function(type, opts){ this.type = type; this.detail = opts ? opts.detail : null; };
g.TouchEvent = function(type, opts){ this.type = type; };
g.WheelEvent = function(type, opts){ this.type = type; };
g.MessageChannel = function(){ return { port1: { postMessage(){}, addEventListener(){} }, port2: { postMessage(){}, addEventListener(){} } }; };
g.addEventListener = function(){}; g.removeEventListener = function(){}; g.dispatchEvent = function(){ return true; };
g.onwheelx = { _Ax: '0X21' };
g.console = { log(){}, warn(){}, error(){}, info(){}, debug(){} };
g.alert = function(){}; g.confirm = function(){ return true; }; g.prompt = function(){ return ''; };
g.open = function(){ return null; }; g.close = function(){}; g.focus = function(){}; g.blur = function(){}; g.print = function(){};

// message handler 捕获
g.webkit = { messageHandlers: { dyyHook: { postMessage(s){ posted.push(String(s)); } } } };

// ---- 运行 hook ----
vm.createContext(sandbox);
try {
  vm.runInContext(code, sandbox, { filename: 'hook.js' });
  check('hook evaluated without throw', true);
} catch (e) {
  check('hook evaluated without throw', false, e.message);
}
check('HOOK_START posted', posted.includes('HOOK_START'));
check('HOOK_INSTALLED posted', posted.includes('HOOK_INSTALLED'));
const cookieMsg = posted.find(p => p.startsWith('COOKIE\n'));
check('COOKIE posted with ttwid', !!cookieMsg && cookieMsg.includes('ttwid'), cookieMsg ? cookieMsg.slice(0, 60) : '');

// ---- 模拟一次页面 fetch（feed 响应）----
const sampleFeed = JSON.stringify({
  aweme_list: [
    { aweme_id: '111', video: { play_addr: { url_list: ['//v26-web.douyinvod.com/a1b2/video/tos/cn/x.mp4?mime_type=video_mp4&dur=10', 'https://www.douyin.com/aweme/v1/play/?video_id=V1'] } } },
    { aweme_id: '222', video: { play_addr: { url_list: ['//v11-weba.douyinvod.com/c3d4/video/tos/cn/y.mp4?mime_type=video_mp4'] } } }
  ]
});
mockResponseText = sampleFeed;
const feedUrl = 'https://www.douyin.com/aweme/v2/web/module/feed/?device_platform=webapp&aid=6383&channel=channel_pc_web&module_id=3003101&count=20&refresh_index=1&refer_id=&refer_type=10&pc_client_type=1&pc_libra_divert=Mac&support_h265=0&support_dash=0&cpu_core_num=4&version_code=170400&video_type_select=1&filter_warn=0&need_fix_st=0&web_page_type=0&os=mac&pull_type=2&is_follow_live=0&poi_data=0&whale_cut_token=&globalId=tobid&msToken=MOCKMS&t';
const hookedFetch = sandbox.fetch; // hook 包装后的 fetch
Promise.resolve(hookedFetch(feedUrl, { credentials: 'include' })).then(() => {
  // 触发所有捕获到的 interval 回调（flush 发布 REQS/VIDEOS 批量；其余为滚动/静音守护）
  for (const t of timers) { if (t[0] === 'interval' && typeof t[1] === 'function') { try { t[1](); } catch (e) {} } }
  // hook 内部 res.clone().text() 是异步微任务，scan 稍后才跑 → 再等一轮后二次 flush，VIDEOS 才会发出
  return new Promise(r => setTimeout(r, 80));
}).then(() => {
  for (const t of timers) { if (t[0] === 'interval' && typeof t[1] === 'function') { try { t[1](); } catch (e) {} } }
  return new Promise(r => setTimeout(r, 30));
}).then(() => {
  const batchMsg = posted.find(p => p.startsWith('BATCH\n'));
  const videosMsg = batchMsg; // VIDS 段在 BATCH 消息内
  check('BATCH combined message posted (single, no overwrite)', !!batchMsg);
  if (batchMsg) {
    const segs = batchMsg.split('\n').slice(1);
    const rIdx = segs.indexOf('REQS'), vIdx = segs.indexOf('VIDS');
    check('BATCH contains REQS section', rIdx >= 0);
    check('BATCH contains VIDS section', vIdx >= 0);
    const vidLines = vIdx >= 0 ? segs.slice(vIdx + 1) : [];
    const reqLines = rIdx >= 0 ? segs.slice(rIdx + 1, vIdx >= 0 ? vIdx : undefined) : [];
    check('VIDS lines tagged + douyinvod extracted', vidLines.some(l => l.includes('douyinvod.com') && l.includes('.mp4')));
    check('VIDS protocol-relative https: prepended', vidLines.every(l => !l.includes(' >> //')));
    check('REQS full-URL captured (>=200 chars)', reqLines.some(l => l.length >= 200), reqLines.length ? 'maxlen=' + Math.max(...reqLines.map(l => l.length)) : '');
  }
  const parsedMsg = posted.find(p => p.startsWith('FEEDPARSED'));
  check('FEEDPARSED reported', !!parsedMsg, parsedMsg || '');
  const badReqs = (batchMsg ? batchMsg.split('\n') : []).filter(l => l.includes('chrome-extension://'));
  check('chrome-extension noise filtered by dedup', badReqs.length === 0, badReqs.length + ' leaked');
  console.log('\n==== RESULT: PASS=' + PASS + ' FAIL=' + FAIL + ' ====');
  process.exit(FAIL === 0 ? 0 : 1);
}).catch(e => { console.log('HARNESS_ERROR ' + e.message); process.exit(2); });
