// a_bogus signature generation wrapper
// Uses bdms (ByteDance Mobile Security) SDK to compute a_bogus for API requests
// This file must be loaded BEFORE bdms.js so that bdms wraps our hooks.
// After bdms.js is loaded, call initABogus() to initialize the SDK.

(function() {
    // Save native XHR methods BEFORE bdms hooks them
    var __captured_url = null;
    var __capture_mode = false;
    var __native_open = XMLHttpRequest.prototype.open;
    var __native_send = XMLHttpRequest.prototype.send;

    // Install our capture hooks - bdms will see these as "the original" open/send
    XMLHttpRequest.prototype.open = function(method, url) {
        if (__capture_mode) {
            // Overwrite each time so the LAST call (from bdms with a_bogus) wins
            __captured_url = url;
            return;
        }
        return __native_open.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function(body) {
        if (__capture_mode) {
            return; // Block actual network request
        }
        return __native_send.apply(this, arguments);
    };

    // Also block fetch during capture
    var __native_fetch = window.fetch;
    window.fetch = function(input, init) {
        if (__capture_mode) {
            return Promise.resolve(new Response('{}'));
        }
        if (__native_fetch) {
            return __native_fetch.apply(this, arguments);
        }
        return Promise.resolve(new Response('{}'));
    };

    /**
     * Initialize bdms SDK. Must be called AFTER bdms.js is loaded.
     */
    window.initABogus = function() {
        if (typeof bdms !== 'undefined' && bdms.init) {
            bdms.init({
                aid: 6383,
                pageId: 6241,
                paths: [
                    "^/webcast/",
                    "^/aweme/v1/",
                    "^/aweme/v2/",
                    "^/live/",
                    "^/captcha/",
                    "^/ecom/"
                ],
                ddrt: 8.5,
                ic: 8.5,
                boe: false
            });
            return true;
        }
        return false;
    };

    // Synthetic URL whose path matches one of the configured `paths` (^/aweme/v1/) so
    // bdms decides it must inject a_bogus. The XHR.send call is intercepted above and
    // never hits the network.
    var __SYNTHETIC_HOST = 'https://www.douyin.com';

    /**
     * Compute a_bogus.
     *
     * Matches DouYin_Spider/static/dy_ab.js -> get_ab(params, data) signature:
     *   - query: URL query string WITHOUT leading '?', e.g.
     *            "device_platform=webapp&aid=6383&...&msToken=..."
     *   - data : POST body string for POST requests, empty string '' for GET.
     *   - uri  : (optional) API URI path, e.g. "/aweme/v1/web/aweme/related/".
     *            Defaults to "/aweme/v1/web/general/search/single/".
     *
     * @returns {string} JSON: {"ok":true,"value":"<a_bogus>"} or {"ok":false,"error":"..."}
     */
    window.getABogus = function (query, data, uri) {
        __capture_mode = true;
        __captured_url = null;

        try {
            var hasBody = (typeof data === 'string' && data.length > 0);
            var path = (typeof uri === 'string' && uri.length > 0) ? uri : '/aweme/v1/web/general/search/single/';
            var url = __SYNTHETIC_HOST + path + (query ? ('?' + query) : '');

            var xhr = new XMLHttpRequest();
            xhr.open(hasBody ? 'POST' : 'GET', url);
            if (hasBody) {
                xhr.send(data);
            } else {
                xhr.send();
            }
        } catch (e) {
            // Ignore errors from blocked network calls
        }

        __capture_mode = false;

        if (__captured_url) {
            var match = __captured_url.match(/[?&]a_bogus=([^&]+)/);
            if (match) {
                return JSON.stringify({ ok: true, value: decodeURIComponent(match[1]) });
            }
        }
        return JSON.stringify({ ok: false, error: 'a_bogus not generated' });
    };
})();
