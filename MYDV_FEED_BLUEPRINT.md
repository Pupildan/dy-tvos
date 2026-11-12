# myDV 数据获取方式 — 照抄蓝图

> **状态：v58 已落地。** §1/§3/§4/§9/§10 已实现进 Swift（DYFeedClient/DYSigner），WebView 泵已全删。
> 剩余未做：扫码登录（拿真实 cookie）、mssdk msToken 网络获取（现用随机兜底）。
> 下一步：真机验证移动端接口连通性 + 签名是否被接受。

> 目标:1:1 复刻 myDV(com.github.mytv.dv,GPL-3.0)的 feed 数据获取到 Swift tvOS 客户端。
> 源头:`u11.java`(= `DouyinDirectApi`)+ 协程伴生类 `sz0/q01` + 会话层 `sl4`。
> 不造轮子:参数名、顺序、host、header、签名链全部照抄,不做"改进"。

反编译产物:`C:\Nbeetok\_apk_work\jadx_out_classes\sources\defpackage\u11.java`(5532 行)。
工具:jadx 1.5.6(`_apk_work\jadx_bin`),JDK17(`_apk_work\jdk`)。

---

## 0. 三条 feed 路径(别再混用)

| 路径 | 方法 | 端点 | Host | UA | 分页游标 |
|---|---|---|---|---|---|
| **移动端推荐(无限刷,首选)** | `V(count, coldStart, seenIds)` | `/aweme/v2/feed/` | `https://aweme.snssdk.com` | 移动端 `p0()` | `refresh_index` 递增 + `cold_start` |
| 网页 tab/feed | `b0(...)` | `/aweme/v1/web/tab/feed/` | `www.douyin.com` | Chrome 桌面 | `offset`(= (page-1)*count) |
| 网页 module/feed | `W(...)` | `/aweme/v2/web/module/feed/` | `www.douyin.com` | Chrome 桌面 | `refresh_index` |

**关键**:你们现在 Swift 里 `DYFeedClient` 回放的正是网页 module/feed 模板,卡 42 条/死锁的根源。
要无限刷 → 改用 `V()` 的移动端 `/aweme/v2/feed/`。

---

## 1. 移动端 `/aweme/v2/feed/` 完整参数(u11.V → sz0)

请求 `GET https://aweme.snssdk.com/aweme/v2/feed/?<params>`,参数**按此顺序**放入 LinkedHashMap:

```
device_platform        = "android"
aid                    = "1128"
channel                = "douyin"
version_code           = "391000"
version_name           = "39.10.0"
os_version             = Build.VERSION.RELEASE (兜底 "16")
os_api                 = Build.VERSION.SDK_INT
language               = "zh"
count                  = "10"            // 每页条数,固定 10
refresh_index          = <递增页码>       // 分页核心:i3,每页 +1
device_id              = <mobile_feed_device_id>   // 来自 sl4 持久化
install_id             = <mobile_feed_install_id>  // 来自 sl4 持久化
cookie_enabled         = "true"
downlink               = "10"
cold_start             = coldStart ? "1" : "0"     // 首页 1,后续 0
refer                  = "1"
pull_type              = coldStart ? "2" : "0"
aweme_rec_raw_data     = <见下,JSON 字符串>
[+ filterGids]         = seenIds.join(",")   // 仅当 seenIds 非空
[+ presented_ids]      = seenIds.join(",")   // 仅当 seenIds 非空
+ (由 D0 追加) msToken / screen_width / screen_height / cpu_core_num /
  device_memory / verifyFp / fp / uifid / webid
+ (由签名链追加) a_bogus
```

`aweme_rec_raw_data`(aweme_rec_raw_data 字段值):
- 冷启动(coldStart=true):
  `{"is_client":false,"ff_danmaku_status":1,"danmaku_switch_status":1,"is_dash_user":1,"related_recommend":1,"is_xigua_user":0,"live_insert_type":0,"insert_ads":0}`
- 非冷启动:
  `{"videoPrefer":{"fsn":[],"like":[<最近20ids>],"halfMin":[<同>],"min":[<同>],"collected":[],"skip":[],"complete_play":[]},"is_client":false,"ff_danmaku_status":1,"danmaku_switch_status":1,"is_dash_user":1,"related_recommend":1,"is_xigua_user":0,"live_insert_type":0,"insert_ads":0}`
  其中 `<最近20ids>` = seenIds 取最近 20 个,逗号连接(u11:2173 `r70.m1(20, list2)`)。

**注意**:移动端参数里 `presented_ids` 是**可选**(seenIds 非空才带),不是网页版那样必带。
分页靠 `refresh_index` 单调递增 + `cold_start` 从 1→0,不是网页版的 offset。

---

## 2. 移动端请求 Headers(sz0:65)

```
User-Agent      : p0()   ← 移动端 UA,见 §3
Accept          : */*
Accept-Language : zh-CN,zh;q=0.9
Cookie          : <sl4.h() 完整 cookie 串,含 sessionid/ttwid/msToken>
```
(移动端**不带** Referer、不带 x-secsdk-web-signature;那是网页版签名链才有的。)

---

## 3. 移动端 UA — p0()(u11:407)

```
com.ss.android.ugc.aweme/391000 (Linux; U; Android <osVersion>; zh_CN; <model>)
```
- `osVersion` = Android 版本号,兜底 "16"
- `model` = 设备型号,兜底 "Pixel 10 Pro";含非 ASCII 时 transliterate,失败也用 "Pixel 10 Pro"

---

## 4. 签名链(移动端简化版,sz0 → u11.C → u11.B → s.c → j)

移动端 feed **只签 a_bogus,不签 x-secsdk-web-signature**:

```
query      = params 拼成 "k=v&k=v"(不含 a_bogus)
a_bogus    = getABogus(query, data="", path="/aweme/v2/feed/", ua=p0())   // ← 4 参!
params["a_bogus"] = a_bogus(仅当非空)
url        = "https://aweme.snssdk.com" + "/aweme/v2/feed/" + "?" + params(k=v&,含a_bogus)
```

### 4.1 getABogus 的 4 参数映射(j.java:68,逐字符核对)

myDV 移动端签名调用是 **4 参数**,顺序固定:
```
getABogus(query, data, path, ua)
```
参数转义(s.b):对每个字符串先做 `\\ → \\\\`、`' → \\'`、`\n → \\n`、`\r → \\r`,再包 `'...'`;
空 data 传 `''`?不——path 为空传 `undefined`,ua 为 null 传 `undefined`。实际:
- 第1参 query = s.b(query)   (非空)
- 第2参 data = s.b(data)     (GET 时是 "",即 `''`)
- 第3参 path = 空?`undefined`:`'<path>'`   (feed 是 `/aweme/v2/feed/`)
- 第4参 ua   = null?`undefined`:`'<ua>'`    (feed 传 p0() 移动端 UA)

JS 侧:`(function(){ try { return getABogus('<query>','<data>', <path>, <ua>); } catch(e){...} })()`
返回 JSON `{ok:bool, value:string}` → s.e() 解析取 value。

### 4.2 ⚠️ 对现有 DYSigner 的改动(照抄的关键一处)

现有 `DYSigner.sign(query:data:uri:)` 只传 3 参 `getABogus(query,data,uri)`,**缺第 4 个 UA**。
且其内部 browser shim 的 navigator.userAgent 绑的是 Safari 桌面 UA。
照抄必须:
1. `sign()` 增加 `ua` 参数,作为 `getABogus` 第 4 参传入;
2. 调用时传 `p0()` 移动端 UA(§3),**不是**现在的 `requestUA`(Safari 桌面);
3. shim 的 navigator.userAgent 也应与该 ua 一致(部分 abogus.js 实现从 navigator 读 UA)。

---

## 5. 网页版签名链(对照,u11.G0 — 仅网页 tab/module feed 用)

移动端不需要,但列出以便理解差异:
```
a_bogus = generateABogus(path, params, method, body)
params["a_bogus"] = a_bogus
timestamp = now/1000
若 UIFID/UIFID_TEMP 存在:
    params["uifid"] = uifid; params["timestamp"] = timestamp
    params["x-secsdk-web-signature"] = MD5(uifid + "_" + timestamp + "_A96D855A08C0A9707F8BEF0D9A527E4E_" + params.join("k=v","&"))
否则: params["timestamp"] = timestamp(不带签名)
```
`i()` MD5 助手见 u11:375。Swift 已有等价能力(加密框架)。

---

## 6. D0 — 公共参数注入(u11:660,所有端点都过一遍)

```
msToken        = cookie.msToken 或 E()(网络获取)或 D()(随机兜底)
screen_width   = dy_swidth 或 "2560"
screen_height  = dy_sheight 或 "1440"
cpu_core_num   = device_web_cpu_core 或 "24"
device_memory  = device_web_memory_size 或 "8"
verifyFp + fp  = s_v_web_id(若 cookie 有)
uifid          = UIFID(若 cookie 有)
webid          = sl4.s()(纯数字时)
```

---

## 7. msToken 兜底(u11.E:724 / D:131)

- `E()`(主路径):POST `https://mssdk.bytedance.com/web/r/token?ms_appid=6383...`(大 JSON body),
  从 Set-Cookie 取 `msToken`(长度 120 或 128)。失败 → `D()`。
- `D()`(兜底):随机 126 位 `[A-Za-z0-9]` + "=="。
- tvOS 上先用 `D()` 随机兜底即可,不必复刻 mssdk 整段 body。

---

## 8. 冷启动初始化(u11.l:3744 → r16 协程)

首次 `V()` 前调 `l()`:若 `sl4.h()`(cookie)空 或 缺 `ttwid` 或 缺 `s_v_web_id` → 走初始化协程
(拉 ttwid:`u11.A()` POST `https://ttwid.bytedance.com/ttwid/union/register/`,
 从 Set-Cookie/body 取 ttwid;再补 s_v_web_id 等),写回 sl4。
`this.f` 标志保证只跑一次。

---

## 9. 响应解析(u11.V:2263)

```
bytes = response.body
FeedResponse = s13.f(bytes)   // kotlinx JSON
items   = FeedResponse.aweme_list  (null→空)
hasMore = FeedResponse.has_more
statusCode==0 正常; 8=需登录; 2154=频率过高; 其他=服务器错误
成功但 items 空 → log hexHead,仍返回(上层决定是否续刷)
```
→ Swift:`JSONDecoder` 解 `aweme_list` + `has_more`,按 `aweme_id` 去重合并进播放池。

---

## 10. 会话存储 sl4(SharedPreferences "douyin_auth")

`u11.a` = sl4。关键取值方法:
- `sl4.i()` → LinkedHashMap 全量 cookie/指纹(含 ttwid / s_v_web_id / msToken / UIFID / UIFID_TEMP / sessionid / dy_swidth / dy_sheight / device_web_cpu_core / device_web_memory_size / bd_ticket_guard_client_data)
- `sl4.h()` → cookie 串
- `sl4.s()` → webid(纯数字)
- `sl4.p(key)` → 单值(mobile_feed_device_id / mobile_feed_install_id)

tvOS 对应:用一个 `DySession` 类持久化这些键(UserDefaults + Cookie jar),`device_id`/`install_id`
首次随机生成后固定,别每次变。

---

## 11. 移植到 Swift 的最小改动清单(DYFeedClient)

1. **host** `www.douyin.com/aweme/v2/web/module/feed/` → `aweme.snssdk.com/aweme/v2/feed/`
2. **UA** Safari 桌面 → `p0()` 移动端 UA(§3)
3. **参数表** → 照 §1 全量替换;删掉 templateURL 模板回放逻辑
4. **分页** → `refresh_index` 从 1 递增,`cold_start` 首页 "1" 其余 "0",`pull_type` 同步(§1)
5. **Headers** → §2(去掉 Referer/sec-fetch-*)
6. **签名** → 复用现有 DYSigner,只签 a_bogus(uri="/aweme/v2/feed/")(§4)
7. **解析** → 读 `has_more` + `aweme_list`,别再靠 `presented_ids` 撑 URL(§9)
8. **会话** → device_id/install_id 固定,msToken 兜底 D()(§7、§10)
9. **不再依赖 WebView 泵** — 移动端接口可直接构造,WebView 只用于扫码登录拿 cookie 一次

---

## 12. 风险与边界

- 移动端 `/aweme/v2/feed/` 无需登录即可刷,但 `device_id`/`install_id` 要稳定,否则风控。
- 现有 DYSigner 的 abogus.js 是网页版 Chrome UA 绑定的;移动端 UA 的 a_bogus **算法相同但 UA 入参不同**,
  必须把 UA 换成 p0() 再喂给签名 JS,否则签名对不上。
- 反编译有 156 处 jadx 错误,但不影响上述关键路径(已逐行核对)。
```
