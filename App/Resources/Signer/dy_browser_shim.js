(function() {
    // ---------- global aliases ----------
    var g = typeof globalThis !== 'undefined' ? globalThis : this;
    g.window = g;
    g.self = g;
    g.top = g;
    g.parent = g;
    g.frames = g;

    // ---------- navigator ----------
    g.navigator = {
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
        appVersion: '5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36',
        platform: 'Win32',
        vendor: 'Google Inc.',
        language: 'zh-CN',
        languages: ['zh-CN', 'zh', 'en'],
        cookieEnabled: true,
        onLine: true,
        hardwareConcurrency: 8,
        maxTouchPoints: 0,
        deviceMemory: 8,
        plugins: { length: 0 },
        mimeTypes: { length: 0 },
        connection: { effectiveType: '4g', downlink: 10, rtt: 50 },
        webdriver: false,
        vendorSubs: { ink: Date.now() }
    };

    // ---------- screen ----------
    g.screen = {
        width: 1920,
        height: 1080,
        availWidth: 1920,
        availHeight: 1040,
        availLeft: 0,
        availTop: 0,
        colorDepth: 24,
        pixelDepth: 24,
        orientation: { angle: 0, type: 'landscape-primary' }
    };

    // ---------- document ----------
    var _cookie = '';
    g.document = {
        body: { clientWidth: 1920, clientHeight: 1040 },
        documentElement: { clientWidth: 1920, clientHeight: 1040 },
        title: '',
        domain: 'douyin.com',
        referrer: '',
        readyState: 'complete',
        hidden: false,
        visibilityState: 'visible',
        location: { href: 'https://www.douyin.com/', protocol: 'https:', host: 'www.douyin.com', hostname: 'www.douyin.com', pathname: '/', origin: 'https://www.douyin.com' },
        createElement: function(tag) {
            return { tagName: tag.toUpperCase(), style: {}, classList: { add: function(){}, remove: function(){}, contains: function(){ return false; } }, setAttribute: function(){}, getAttribute: function(){ return null; }, appendChild: function(){}, removeChild: function(){}, addEventListener: function(){}, removeEventListener: function(){}, getBoundingClientRect: function(){ return {top:0,left:0,bottom:0,right:0,width:0,height:0}; }, offsetWidth: 0, offsetHeight: 0 };
        },
        createTextNode: function(text) {
            return { nodeValue: text, textContent: text, data: text };
        },
        getElementById: function() { return null; },
        getElementsByTagName: function() { return []; },
        getElementsByClassName: function() { return []; },
        querySelector: function() { return null; },
        querySelectorAll: function() { return []; },
        addEventListener: function() {},
        removeEventListener: function() {},
        createEvent: function() { return { initEvent: function(){}, preventDefault: function(){}, stopPropagation: function(){} }; }
    };
    // document.cookie getter/setter via defineProperty
    Object.defineProperty(g.document, 'cookie', {
        get: function() { return _cookie; },
        set: function(v) {
            var parts = v.split(';');
            if (parts[0]) {
                var kv = parts[0].trim();
                var eq = kv.indexOf('=');
                if (eq > 0) {
                    var key = kv.substring(0, eq).trim();
                    var val = kv.substring(eq + 1).trim();
                    var cookies = _cookie.split('; ').filter(function(c){ return c && c.indexOf(key + '=') !== 0; });
                    cookies.push(key + '=' + val);
                    _cookie = cookies.join('; ');
                }
            }
        }
    });

    // ---------- location ----------
    g.location = g.document.location;

    // ---------- window dimensions ----------
    g.innerWidth = 1920;
    g.innerHeight = 1040;
    g.outerWidth = 1920;
    g.outerHeight = 1080;
    g.screenX = 0;
    g.screenY = 0;
    g.pageXOffset = 0;
    g.pageYOffset = 0;
    g.scrollX = 0;
    g.scrollY = 0;
    g.devicePixelRatio = 1;

    // ---------- XMLHttpRequest (minimal stub) ----------
    g.XMLHttpRequest = function() {
        this.readyState = 0;
        this.status = 0;
        this.statusText = '';
        this.responseText = '';
        this.responseURL = '';
        this.withCredentials = false;
        this.__method = '';
        this.__url = '';
        this.__headers = {};
        this.__body = null;
    };
    g.XMLHttpRequest.UNSENT = 0;
    g.XMLHttpRequest.OPENED = 1;
    g.XMLHttpRequest.HEADERS_RECEIVED = 2;
    g.XMLHttpRequest.LOADING = 3;
    g.XMLHttpRequest.DONE = 4;
    g.XMLHttpRequest.prototype.open = function(method, url, async, user, pass) {
        this.__method = method;
        this.__url = url;
        this.readyState = 1;
    };
    g.XMLHttpRequest.prototype.send = function(body) {
        this.__body = body || null;
    };
    g.XMLHttpRequest.prototype.abort = function() {};
    g.XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
        this.__headers[name] = value;
    };
    g.XMLHttpRequest.prototype.getResponseHeader = function() { return null; };
    g.XMLHttpRequest.prototype.getAllResponseHeaders = function() { return ''; };
    g.XMLHttpRequest.prototype.addEventListener = function() {};
    g.XMLHttpRequest.prototype.removeEventListener = function() {};

    // ---------- fetch (stub) ----------
    g.fetch = function(input, init) {
        return Promise.resolve({ ok: true, status: 200, json: function(){ return Promise.resolve({}); }, text: function(){ return Promise.resolve(''); } });
    };

    // ---------- timers ----------
    var _timerId = 0;
    g.setTimeout = function(fn, ms) { var id = ++_timerId; if (typeof fn === 'function') { try { fn(); } catch(e) {} } return id; };
    g.setInterval = function(fn, ms) { return ++_timerId; };
    g.clearTimeout = function(id) {};
    g.clearInterval = function(id) {};
    g.requestAnimationFrame = function(fn) { return ++_timerId; };
    g.cancelAnimationFrame = function(id) {};

    // ---------- localStorage / sessionStorage ----------
    var _storage = {};
    g.localStorage = {
        getItem: function(k) { return _storage[k] || null; },
        setItem: function(k, v) { _storage[k] = String(v); },
        removeItem: function(k) { delete _storage[k]; },
        clear: function() { _storage = {}; },
        get length() { return Object.keys(_storage).length; },
        key: function(i) { return Object.keys(_storage)[i] || null; }
    };
    g.sessionStorage = g.localStorage;

    // ---------- crypto ----------
    g.crypto = {
        getRandomValues: function(arr) {
            for (var i = 0; i < arr.length; i++) {
                arr[i] = Math.floor(Math.random() * 256);
            }
            return arr;
        },
        subtle: {
            digest: function() { return Promise.resolve(new ArrayBuffer(32)); }
        }
    };

    // ---------- performance ----------
    var _perfStart = Date.now();
    g.performance = {
        now: function() { return Date.now() - _perfStart; },
        timing: { navigationStart: _perfStart, fetchStart: _perfStart, domainLookupStart: _perfStart, domainLookupEnd: _perfStart, connectStart: _perfStart, connectEnd: _perfStart, requestStart: _perfStart, responseStart: _perfStart, responseEnd: _perfStart, domLoading: _perfStart, domInteractive: _perfStart, domContentLoadedEventStart: _perfStart, domContentLoadedEventEnd: _perfStart, domComplete: _perfStart, loadEventStart: _perfStart, loadEventEnd: _perfStart },
        getEntries: function() { return []; },
        getEntriesByType: function() { return []; },
        getEntriesByName: function() { return []; },
        mark: function() {},
        measure: function() {}
    };

    // ---------- atob / btoa ----------
    var _b64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    g.btoa = function(s) {
        var r = '';
        for (var i = 0; i < s.length; i += 3) {
            var n = s.charCodeAt(i) << 16 | (s.charCodeAt(i+1) || 0) << 8 | (s.charCodeAt(i+2) || 0);
            for (var j = 0; j < 4; j++) {
                if (i * 8 + j * 6 <= s.length * 8) r += _b64.charAt((n >>> 6 * (3 - j)) & 63);
                else r += '=';
            }
        }
        return r;
    };
    g.atob = function(s) {
        var b64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
        s = s.replace(/\s/g, '');
        var r = '';
        for (var i = 0; i < s.length; i += 4) {
            var n = 0, cnt = 0;
            for (var j = 0; j < 4; j++) {
                if (i + j < s.length && s.charAt(i + j) !== '=') {
                    n = (n << 6) | b64.indexOf(s.charAt(i + j));
                    cnt++;
                } else {
                    n <<= 6;
                }
            }
            var bytes = cnt - 1;
            for (var j = 2; j > 2 - bytes; j--) {
                r += String.fromCharCode((n >>> (j * 8)) & 255);
            }
        }
        return r;
    };

    // ---------- misc ----------
    g.history = { pushState: function(){}, replaceState: function(){}, go: function(){}, back: function(){}, forward: function(){}, length: 0 };
    g.alert = function(){};
    g.confirm = function(){ return true; };
    g.prompt = function(){ return ''; };
    g.open = function(){ return null; };
    g.close = function(){};
    g.focus = function(){};
    g.blur = function(){};
    g.print = function(){};
    g.getComputedStyle = function() { return new Proxy({}, { get: function(t, p) { return ''; } }); };
    g.matchMedia = function() { return { matches: false, addListener: function(){}, removeListener: function(){}, addEventListener: function(){}, removeEventListener: function(){} }; };
    g.Image = function() { return {}; };
    g.MutationObserver = function() { return { observe: function(){}, disconnect: function(){}, takeRecords: function(){ return []; } }; };
    g.IntersectionObserver = function() { return { observe: function(){}, disconnect: function(){} }; };
    g.ResizeObserver = function() { return { observe: function(){}, disconnect: function(){} }; };
    g.Worker = function() { return { postMessage: function(){}, terminate: function(){} }; };
    g.Event = function(type) { this.type = type; };
    g.CustomEvent = function(type, opts) { this.type = type; this.detail = opts ? opts.detail : null; };
    g.MessageChannel = function() { this.port1 = { postMessage: function(){}, addEventListener: function(){} }; this.port2 = { postMessage: function(){}, addEventListener: function(){} }; };

    // ---------- window event stubs ----------
    g.addEventListener = function() {};
    g.removeEventListener = function() {};
    g.dispatchEvent = function() { return true; };

    // ---------- window.onwheelx (dy_ab.js compat) ----------
    g.onwheelx = { _Ax: '0X21' };

    // ---------- console (map to no-op; QuickJS has its own) ----------
    if (typeof g.console === 'undefined') {
        g.console = { log: function(){}, warn: function(){}, error: function(){}, info: function(){}, debug: function(){} };
    }
})();