# DYTV 交接文档（v162 · 2026-11-15 全面重构版）

> **维护规则（v148 起）**：新内容只更新对应章节（§5 未解决/§6 踩坑/§8 方向/§7 字段表），不再按版本堆叠新章节；版本细节以 git log + 记忆文件为准。

> 本文档取代此前所有过时交接。所有结论均基于工具读取的实际代码与日志，非记忆。
> **当前版本 v172**。稳定回退点：**v122**（git checkout 三文件）。
> 最新验收状态：播放线全收工（v128-v131 "趋近完美"）；双源架构全通（v135）；弹幕空窗真根因已修（v151-152）；两倍速=确认键长按 0.6s（v156 定版）；评论死锁修复（v149）；**作者资料+作品列表=WebView 截获路线真机全通**（v163-v168）；点播/焦点/滑动/自动加载全修通（v169-v171）；v172=右轨统计+insertWorks 回推荐流+合集屏（mix/aweme 页面上下文 fetch，待验收）。

---

## 1. 项目概述与铁律

纯原生 tvOS 抖音客户端（sideload 自用）。三条铁律：
1. **绝对不使用 WebView 作为 UI**。
2. **真实视频层滑动是核心体验，必须保留**（不能退回快照假滑动）。
3. **绝对禁止造轮子**：未知字段/解析/清晰度不准猜，必须翻反编译（`_apk_work/jadx_out_classes` + `_apk_work/jadx_out`）找 myDV（com.github.mytv.dv, GPL-3.0）现成源码照抄。v94-v99、v111-v124 反复因"造轮子/幻觉"翻车，这是最高教训。

## 2. 环境与构建

- **开发机 Windows 无 Xcode** → 全靠 GitHub Actions CI + 真机（ATV，tvOS 26）。
- 流水线 `_tools/dy_pipeline.ps1 -Version vX -CommitMsg "..."`：commit→push→盯 CI→下载 ipa 到 `output/`。版本号 `DYBuild.version` 每次 +1 禁止重复（失败无产物可复用版本号）。
- **CI 失败**：`_tools/dy_fetch_errors.ps1 -RunId <id>` 抓错误行。
- **CI 成功但下载抽风**（已知瞬态）：`_tools/dy_download.ps1 -ArtifactId <id> -IpaName "DYTV-tvos-unsigned-vXX.ipa"` 单独重下，**不要重跑整条 pipeline**（会双重 commit/push）。
- git 在 `C:\Users\Admin\WorkBuddy\fndanmu-tvos\_tools\MinGit\cmd\git.exe`。
- 日志：ATV 推送到开发机 `output/atv_push.log`（`dy_collector.ps1` 监听 :9988）。**采集器不会常驻**——读日志前 `netstat -ano | findstr :9988` 确认 LISTENING；ATV 只在新日志产生时重连（采集器起来后要操作一下 ATV 触发回灌）；ATV IP 从 9988 的 ESTABLISHED 远端拿。
- 真机诊断：`curl http://<ATV-IP>:8765/stat`（计数器+事件环）/ `/log`。
- **开发机验证门（重大流程，用户提议采纳）**：数据获取类改动先用 Node 复刻整条链验证（`_tmp/danmaku_probe.js` / `webfeed_probe.js` / `danmaku_hist_probe.js` / `comment_works_probe.js` 可复用：加载 Signer JS + protobuf 解码 + HTTP 矩阵），数据说话后再进真机——一轮脚本顶 3-4 轮 CI。

## 3. 当前架构（v147 实际状态）

- **数据层** `DYFeedClient`：双源。
  - mobile：`aweme.snssdk.com/aweme/v2/feed/` protobuf 直连（`DYSigner` JavaScriptCore 4 参 getABogus(query,data,path,ua)，`Proto` 手工 wire 解码）。
  - web（抖音精选）：`www.douyin.com/aweme/v1/web/tab/feed/` JSON（b0 配方 + webCommon + web 签名 + ttwid）。
  - 源切换：`DYFeedSource` 枚举 + `setSource()`（持久化 UserDefaults dy_feed_source）+ `PlaybackEngine.reset()`。
- **播放层** `NativePlayerView`：UICollectionView 垂直分页 + PlayerManager 池（±2 窗口驱逐）+ 三层看门狗 + 冷启动收敛 + 源感知请求头 + PC 版 UI（右轨/左下信息区/进度条）。
- **弹幕**（v149-v150 按用户规格重造）：DYDanmakuClient（web get_v2 分段）+ DanmakuKit vendor + DYDanmakuOverlay（shotIds 发射器）。数据链全通（取数 1-7s 全量、0 重试）。显示端：**顶部 6 行（轨道高 50）/ 禁止重叠 / 280px/s**；发射器 v150 canShoot 门控（被轨道拒不标记，腾出即补射）+ 轨道卡死 10s 自愈（DMJANITOR 强制清轨）+ DMSYNC 每 4s 诊断日志。
- **快捷悬浮窗**（DYQuickPanel）：确认键短按呼出，**屏幕底部居中横向卡片**（RootView ZStack 是 alignment:.leading，外层 VStack 必须 frame(maxWidth:.infinity) 才不被钉在左侧）；标准液态玻璃无 tint 透出视频；主页/评论/合集(条件)/不感兴趣。**两倍速=长按确认键 0.6s 松开恢复**（v156-v158 反复后定版+图上方案 0.8s/10px 紧容差实测仍不稳，**触摸悬停共试 11 版全部失败已终删**——Siri Remote 触摸悬停永不再试）。
- **评论**（DYCommentClient + DYCommentScreen）：web comment/list，3 页 60 条，玻璃列表屏。
- **设置面板**（DYSettingsModel + SettingsPanelView）：Menu 呼出，左侧液态玻璃，源切换/弹幕开关/占位项，3s 自动隐藏。

## 4. 版本里程碑（压缩史——细节查 git/记忆文件）

| 版本 | 内容 | 状态 |
|---|---|---|
| v122 | 稳定基线（跳多页/声画/冻屏修复） | ✅ 验收，回退点 |
| v128 | 黑屏三靶点（重定向新鲜 URL/空轨检测/isReadyForDisplay 看门狗） | ✅ "体验有很大提升" |
| v129 | parse 无感过滤图集/novideo（实际全靠 dur=0 信号） | ✅ "趋近完美" |
| v130 | 冷启动收敛 + idle 4s→2s | ✅ "提速不少" |
| v131 | 去水印（play_addr 优先 + selectBestPlayUrl 四级） | ✅ "水印没了，趋于完美" |
| v132-v142 | 弹幕五轮（数据链打通→样式→断流→自适应切分→平滑发射） | ⏸️ 用户暂停：改法没到点子 |
| v135 | 设置面板 + 双源 + 液态玻璃 | ✅ 验收全通 |
| v136/v137 | 面板 3s 隐藏+焦点白描边 / 源持久化 | ✅ |
| v138/v139/v140 | 弹幕断流三轮（分段/重试/自适应切分）+进度条 | 数据面净，显示面未达点子 |
| v141 | 显示吞吐提升（34 轨高/75% 区/380px/s） | 仍间歇（后查明=发射器机制） |
| v142 | 每 tick 限量 6 条平滑发射 + isOverlap | ⏸️ 用户暂停 |
| v143/v144 | PC 版 UI（右轨/左下信息区/进度条）+ 五点反馈修正 | ✅ 待复验 |
| v145 | 快捷悬浮窗（OK 呼出四项）+ 间距收紧 + 图标加大 + 时长文本 | ✅ 待复验 |
| v146 | 触摸板滑动切换 + 长按 1.5s 两倍速 + 头像正圆 | ✅ 待复验 |
| v147 | 确认键修正（.select）+ 评论功能实装 + 播放/暂停键恢复 | ✅ CI 过，待验收 |
| v148 | 评论屏闪退修复（tvOS 焦点环境无可聚焦元素，真机日志实锤）+ 两倍速改长按确认键 0.6s + 快捷面板底部居中横排 + 右轨图标加大 | ❌ 焦点理论证伪（v148 真机评论仍闪退），但焦点兜底保留 |
| v149 | 评论闪退真根因=ensureTTWID 队列内联回调+同队列 queue.sync 自等待死锁；两倍速改触摸板悬停 1s；面板真·底部居中+无 tint 玻璃；弹幕顶部 6 行/不重叠/280px/s；右轨图标回落 | ✅ 评论死锁修复真机验收通过（v149 会话 3 次开评论屏 0 闪退，CMT 全通）；触摸悬停真机零触发（容限太紧） |
| v150 | 弹幕 canShoot 门控+轨道卡死 10s 自愈+DMSYNC 诊断；行距加大（轨道高 50）；悬停倍速 0.6s/漂移容限 140/必留日志+▶▶2x 角标；主页合集 toast 反馈（探针实锤作品列表需登录态） | ✅ DMSYNC 立功：发射层无恙，暴露取数缺口 |
| v151 | **弹幕空窗真根因**=服务端单请求最多回 ~30s 数据、60s 窗口永久丢后半段（1199 vs 1981 探针对比）→窗口 20s 重叠覆盖；标题重复=desc 内联话题词法剔除；非全屏黑边取色高斯模糊背景；悬停倍速 pan 小位移兜底双通道 | ✅ 弹幕真机验证全量（29632 条/stall=0）；悬停暴露滑动互斥问题；模糊层空白 |
| v152 | 悬停/滑动互斥判定（一次触摸二选一，悬停阈值放宽 100px，2x 中漂移不再切视频）；loadCover 无条件调用修氛围层空白（只对未就绪视频加载导致预载就绪视频永无封面）；ambient_ok/fail 计数 | ⚠️ 悬停仍要位移才触发（pan 抢杀 LongPress）；模糊效果用户不满意 |
| v153 | **悬停纯计时触发**（手势共存委托：v149-v152 的 LongPress 被 pan 默认互斥规则在手指移动 10px 时强杀，纯静止触摸到不了 0.6s）；撤销模糊背景；**作者主页实装**（DYProfileClient：UIFID_TEMP cookie 罐 + uifid 参数/头 + x-secsdk-web-signature MD5 照抄 u11.i()；user/profile/other 匿名全通；aweme/post 真机试探埋日志） | ✅ **主页真机通**（PROFILE ok fans=86512 works=721）；作品列表真机也 200 空（TLS 理论证伪）；悬停触摸仍不可靠 |
| v154 | 两倍速改长按确认键 0.6s + 触摸悬停逻辑全部删除 | ⚠️ 用户短暂反悔改 v155，未装机 |
| v155 | 撤销 v154 恢复触摸悬停 | ⚠️ 用户多次实测触发仍不稳定，已作废不装 |
| v156 | **最终定版=长按确认键 0.6s 触发两倍速、松开恢复、短按呼出快捷面板**（=v154 代码，NativePlayerView 从 3bb022d 恢复）；触摸悬停逻辑删干净避免与滑动冲突 | ✅ 真机可用 |
| v157 | 主页深挖：补齐 myDV 静态浏览器头 n（u11:80）+ mssdk 真 msToken（DYMsSdk.swift 程序化照抄 u11:729）+ aweme/detail 探针全通 | ❌ **浏览器一致性头与 URLSession 指纹自相矛盾触发风控，资料接口 200 空**（v153 最小头才是可用态）；真机 mssdk MISS |
| v158 | ①资料接口回退 v153 最小头配方；②触摸倍速按图上方案实现（0.8s/10px 紧容差/失败排序）；③确认键长按保留 | ❌ 触摸悬停真机仍不触发——**用户拍板最终删除** |
| v159 | **触摸悬停最终删除**（恢复 v156 手势）；主页深挖：反编译 classes2/3.dex 得 myDV 完整 UI 层——作品=aweme/post、作者合集列表=**series/list（探针全通 sc=0，字段 series_infos）**、合集内容=series/aweme/aweme/detail；发现 **z() 引导**（u11:5400） | ✅ 真机定论：URLSession 也被 jsvmp 挑战页拦（challenge=1） |
| v160 | 隐形 WebView 引导第一版（公开 WebKit 模块） | ❌ CI 实锤 **tvOS 无公开 WebKit**（unable to resolve WebKit） |
| v161 | **改回 v2-v8 真机验证过的私有方案**：DYWebViewShim.m 回归（dlopen 私有 WebKit.framework + objc_msgSend 建 WKWebView，桥接头 DYTV-Bridging-Header.h + project.yml SWIFT_OBJC_BRIDGING_HEADER）+ 引导改 isLoading 轮询 + evaluateJavaScript 收 document.cookie（挑战页 JS 种的 s_v_web_id/__ac_signature/uifid）+ 失败 2s 重试 6 轮 + 20s 兜底 | ✅ **真机引导成功**（WEBBOOT 收到 __ac_signature+s_v_web_id）；资料时好时坏=连发限流 |
| v162 | **资料获取稳定化**：按作者缓存 10 分钟 + 请求节流 ≥1.5s + 空响应自动重试一次 + 作品探测每会话每作者一次 + 资料屏失败态提示（连发限流是"时好时坏"根因：快速切作者时第一发过、第二发被静默拒） | ✅ CI 过，待验收 |
| v163 | **作品列表转 WebView 截获路线（用户拍板降维打击）**：本地算 a_bogus 判死（见 §5.3③★）→ 放弃 Swift 侧签名，新增 `DYWorksCapture`：离屏 WebView 加载作者主页 + XHR/fetch 覆写把页面自算的真 168 签名 aweme/post 响应体塞 `window.__dyCap` + 轮询 evaluateJavaScript 抽回 + 全量日志（WORKS CAP）。铁律边界=离屏数据泵非 UI，复用 v161 已验证 evaluateJavaScript 通道零新 ObjC。RootView onChange(isProfileOpen) 触发 | ✅ CI 过，**待真机验证截获成立** |
| v164/v165 | 零截获修复：hook 改 WKUserContentController **document-start 注入**（v165：先配 controller 再 initWithFrame + evaluateJavaScript 补装兜底） | ✅ 真机 hooked=1，截获成立 |
| v166/v167 | 资料接 UI：截获 profile/other → DYProfileUser → DYProfileScreen；v167 CI 修 Delegate 协议去 AnyObject（DYProfileScreen 是 struct，strong delegate） | ✅ **真机资料 100% 通**（136 万粉大 V 也通） |
| v168 | 作品网格+点播：aweme/post 改 **JS 端预解析精简**（300KB 截断根因，体积→~10KB）+ `DYCapturedWork` 模型 + 网格 UI + tap 经 engine merge 播放 | ✅ CI 过；真机截获 n=18/21 通，但点播/焦点翻车（v169/v170 修） |
| v169 | 网格 `.focused` 绑定（tvOS 焦点引擎要求）+ 播放器/网格合集角标 + JS 提取 mix_info | ⚠️ 真机：点播被吃/无焦点视觉/自动加载不生效（日志实锤三根因，v170 修） |
| v170 | **三连修复**：①点播不生效真根因=playWork 只改 engine.index 没通知 collection，下一按 reconcile 循环把 index 退回旧视觉位置（ENGINE prev 连环实锤）→ 发 `DYWorksJump` 通知让播放层 scrollTo；②聚焦视觉（白描边+放大+首批到达自动聚焦第一个作品）；③自动加载=首批即 teardown 真凶 → 累积去重+持续滚动截获（停滞 15s/60s 收摊） | ✅ CI 过；真机点播正确（works jump idx 精准），但暴露两新坑（v171 修） |
| v171 | ①点作品播别的视频=jump 同步通知时 insertItems 未跑，targetY 被旧 contentSize 钳底 → jumpToWorksIndex 轮询等 item 就绪再滚；②作者页滑动穿透切视频=handlePan 没护栏 isProfileOpen/isCommentOpen → 焦点屏打开时 pan/pressesBegan 全放行焦点引擎 | ✅ 真机点播/滑动正确；暴露右轨无数据/回不到推荐流/合集占位（v172 修） |
| v172 | ①右轨数据：JS 提取 statistics（赞/评/藏/享）→ DYCapturedWork → DYVideoInfo；②回推荐流：`insertWorks` 插入式重建（已看 feed 前缀+作品段+feed 剩余）替代尾部 append，down 刷完作品自动滑回 feed；③合集实装：DYVideoInfo 补 mixId（f14 f6/mix_info）→ 快捷面板合集项 → DYMixScreen → `fetchMix` 页面上下文 fetch mix/aweme（§5.3⑤A 路线首次实装，页面 fetch 包装带签名）→ hook 拦截 → 网格点播 | ✅ CI 过，待真机验收（MIXCAP 日志行=合集链路是否成立的关键证据） |

## 5. 未解决问题清单（按优先级）

### 5.1 新视频卡顿（播放体验，用户未拍板方案）
- **现象**：刷到新视频后过几秒才触发播放（forward ready 0-3s，用户刷速快于预载；回看旧视频走 redirect 0-16s）。
- **已分析根因**：①每视频不同 CDN 域名 → 每次 acquire 新 DNS+TLS；②驱逐半径 ±2 窄，回看必重取；③v136 idle=2s 有误杀风险（本会话未触发但存在）；④redirect 302 出的 CDN 不可控（16s 尾部）。
- **候选方案（待拍板）**：A 驱逐半径对称 ±3（解码器 ≤7 仍限内）；B idle 2s→4s 回退；C redirect>5s fallback static 重试；D 预取窗口 [idx-1, idx+3] 前向偏移。建议组合 A+B+D。

### 5.2 弹幕间歇空窗（v151 真根因已修复：服务端 30s 响应上限，待验收）
- **真根因（v150 DMSYNC 日志 + 探针对比实锤）**：danmaku get_v2 **服务端单次请求最多只回 ~25-30s 的数据**（start_time 起算，end_time 超出被忽略）。v138-v150 的 60s 窗口=每个窗口后半段永久丢失（同一 14min 视频：60s 窗口取 1199 条 vs 30s 窗口取 1981 条）→「播 ~30s 有弹幕→断 ~30s→下一窗口前半段又有」的完美循环。v138 当年的验收只对比了"比之前多"，没验证完整性，漏掉了这个坑。
- **修复**：segmentWindowMs 60s→20s（服务端返回 [start-3s, start+25s] ⊇ 20s 请求窗，seen 去重重叠覆盖全量）；cap-hit 自适应拆分保留。
- **V150 已修并保留的**：发射器 canShoot 门控（被轨道拒不标记、腾出即补射）；DMJANITOR 轨道卡死 10s 自愈；DMSYNC 每 4s 诊断日志；顶部 6 行/不重叠/280px/s/轨道高 50。
- **验收点**：长视频弹幕应全程连续无 30s 级空窗；日志 DMSYNC stall 应持续 ≤2（不再出现 stall=100+）；DMJANITOR 不应触发。

### 5.3 作者作品与合集内容（❌ 未解决——攻坚全记录，接手必读）

**当前状态一句话（v170 更新）**：**作品列表已破局**——WebView 截获路线真机全通（页面自己算 168 签名，我们拦响应体；资料+首批作品真机成立）；Swift 侧签名链全部打通但 aweme/post 直连仍 200 空（保留以下攻坚记录供参考，勿再走直连老路）。资料屏/作品网格/自动加载在 v169-v170 打磨中。

#### ① 已实装且真机可用的
- **user/profile/other**（作者资料）：匿名全通。配方=v153 最小头（假 msToken + 最小头 + UIFID_TEMP 罐 + uifid 参数/头 + x-secsdk 签名），真机多次 fans/works 真实数据。**⚠️ v157 教训：给这条链加浏览器一致性头（sec-ch-ua 等）会把它也搞挂——头声称"我是浏览器"但 URLSession 指纹不是 = 自相矛盾触发风控。这条链永远用最小头。**
- **资料稳定化**（v162）：按作者缓存 10 分钟 + 请求节流 ≥1.5s + 空响应自动重试一次 + 作品探测每会话每作者一次 + 资料屏失败态。根因=连发限流（日志实锤：快速切作者时第一发过、第二发 200 空）。

#### ② 身份链组件全部打通并被验证（可直接复用）
- **UIFID_TEMP**：`tab/feed` 响应 `Set-Cookie` 自动下发（160 hex）——不需要申请端点，cookie 罐收走即可。之前的 403 "Uifid Not Found" 就是缺它 + `uifid` 参数/头。
- **x-secsdk-web-signature**：`MD5(uifid_timestamp_A96D855A08C0A9707F8BEF0D9A527E4E_全参数k=v&拼接)`（u11.i() 原样，参数含 a_bogus+uifid+timestamp）。签名错=403 "Sign Invalid"；对=过签名关。
- **隐形 WebView 引导**（v161 真机成功）：tvOS 无公开 WebKit → dlopen 私有框架三件套（DYWebViewShim.h/.m + DYTV-Bridging-Header.h + project.yml SWIFT_OBJC_BRIDGING_HEADER，均在 v8 commit 77447bc）。离屏 1x1 WebView 加载抖音首页 → jsvmp 挑战 JS 自动种下 **__ac_signature + s_v_web_id**（document.cookie 收割成功，日志 WEBBOOT 行）。
- **aweme/detail** 探针全通（视频详情真实数据，参数 aweme_id/request_source=600/origin_type=quick_player）。
- **series/list** 探针全通（sc=0，作者合集列表，字段 series_infos——但样本作者恰无短剧，series_infos=null；**未验证：有合集的作者返回什么、series_id 与 feed f14 的 mix_id 是否同一 id 空间**）。

#### ③ 未解决的两点
- **aweme/post（作品列表）**：签名通过但 **200 + content-length:0 静默拒绝**。已排除（全部探针/真机双重验证）：TLS 指纹（真机 URLSession 也空）、真 msToken（mssdk 照抄 u11:729 可换，带上也空）、全套浏览器一致性头（反而打挂 profile，见 ①）、webid、verifyFp/fp、参数矩阵（最小/完整/无 locate/from_user_page 开关）、预热会话、多作者。**剩余假设：服务端设备/会话信任级判定（jsvmp 挑战通过后的"完整浏览器 cookie 状态"——odin_tt 等 HttpOnly cookie document.cookie 不可见，无法收割）**。
- **合集内容**：`mix/aweme` sc=4（参数错）；`series/aweme` 用 mix_id 传 → sc=5（不认）；`mix/detail` sc=0 但 mix_info 空；`series/list` 通但样本作者无数据。**未验证：有短剧/合集作者的 series/list 返回内容 + series/aweme 用其真实 series_id**。

#### ③★ 2026-11-15 真机抓包突破（推翻③的 odin_tt 假设——接手必读）
KernelSU 临时 root + mitmproxy（CA bind-mount 进 Android16 apex+system cacerts）抓 myDV(安卓 v2.3.45)真机流量，**首次拿到 aweme/post = 200 + 212KB 真实作品数据**。四轮 Node 重放对照探针（`C:\Nbeetok\_tmp\mitm\aweme_post_{replay,var,mstoken}_probe.js`）钉死因果：
- **✅ 命门 = 真 msToken**：aweme/post 出数据 ⇔「URL参数位 msToken」或「Cookie位 msToken」**至少一处真值**。两处都随机/缺=**403明确拒**。参数真→cookie无也过(G/H)；cookie真→参数随机也过(B)。
- **❌ 全都无关（推翻旧方向）**：odin_tt、web_sign_token、浏览器一致性头 sec-ch-ua/sec-fetch——去掉照样 200。③押注的"收 HttpOnly odin_tt"方向**多走了一步，别再走**。
- **✅ 不用登录**：myDV 拿作品无 sessionid/sessionid_ss，纯匿名态，风控≈刷电脑版流（用户最怕登录风控，此路解之）。
- **⚠️ 真根因已锁定（2026-11-15 自签探针，接手必读）**：用**我们自己签名器**（`App/Resources/Signer/abogus_dy.js` 链：dy_browser_shim→abogus→sign→abogus_dy→getABogus，Node vm 1:1 复刻 DYSigner.swift）自签 a_bogus 打 aweme/post = **200 空**——开发机 Node 就复现了 tvOS bug，**证明与真机 TLS 指纹无关**。全套 myDV 参数+自签仍 200 空 → 排除参数缺失。**铁证 = 签名长度不对：我们 a_bogus len=180，myDV len=168**。而 myDV 原样 URL + 活 cookie = 200 带 3 条作品（cookie 仍活）。→ **tvOS「200 空」真因 = 我们捆绑的签名器生成的 a_bogus 是错误/版本不匹配算法**（服务端验签不过 → 200 空软拒），与 msToken/odin_tt/参数/TLS **全无关**（本会话前面 msToken 假设是用 myDV 活签名重放误入的歧途，已废弃，别再走）。**修复路线 = 从 myDV APK assets 提取网页端正确的 a_bogus 生成器（168 长度版）替换 abogus_dy.js**，或让 tvOS 改走 myDV 网页端实际用的签名路径。抓包链/探针（`_tmp/mitm/*_probe.js`）/防火墙坑见记忆 `dytv-aweme-post-capture-breakthrough`。

#### ④ 排错过程时间线（每步都是实测，接手者别重复）
1. v147：web aweme/post → 403 `ArgusSecurityPlugin Uifid Not Found`（当时只知道缺 UIFID）。
2. 探针矩阵试 mobile `/aweme/v1|v2/aweme/post/`（sec_user_id/user_id 两种形态 × 3 作者）→ status_code=0 但**匿名一律空列表**——mobile 路径是登录态墙。
3. 反编译 UI 层前先找到 **UIFID_TEMP 真来源**：`tab/feed` 响应 Set-Cookie 下发（对照实验：60s 窗口取 1199 vs 30s 窗口 1981 是弹幕的事，别混淆）。
4. 找到 myDV 签名链：u11.i()（x-secsdk MD5，密钥 A96D855A08C0A9707F8BEF0D9A527E4E）+ G0/withUserCenterSignChain（uifid 参数+timestamp+x-secsdk）+ rz0（uifid 头）。探针验证：签名错=403 "Sign Invalid"，对=过签名关——**公式正确**。
5. 5 轮探针把参数/头/cookie 全复刻后 post 仍 200 空；真 msToken（mssdk u11:729 strData 9.5KB 程序化提取 DYMsSdk.swift）带上也空；浏览器一致性头加上反而打挂 profile（v157 回归，v158 回退）。
6. 反编译 **classes2/3.dex**（之前只反编译了 classes.dex！UI 层 146 类）→ ProfileViewModel(ux3/nx3) 实锤：作品=aweme/post(k0)、作者合集列表=series/list(h0)、合集内容=series/aweme(T，mix_id 当 series_id 传)——端点全对，但行为层面仍被拒。
7. 发现 **z() 引导**（u11:5400）：首页 GET 手动跟随重定向 ≤5 跳吸 Set-Cookie + y() 解析 HTML 内嵌 msToken/odin_tt/user_unique_id(=webid)。Node 探针复刻 → **100% 被 jsvmp 挑战页拦**（72914 字节空 body JS VM 页，`_$jsvmprt` 特征）。
8. v159 真机验证：**URLSession 也被挑战页拦**（challenge=1）——TLS 指纹理论彻底死。
9. 用户拍板**隐形 WebView 引导**（v160 公开 WebKit 模块编译失败——tvOS 无公开 WebKit；v161 改回 v2-v8 私有 shim 方案）→ **真机收割 __ac_signature+s_v_web_id 成功**。
10. v162 稳定化资料（缓存/节流/重试）——但 **post 仍然 200 空**：挑战页 JS 种的 cookie 里 odin_tt 等 HttpOnly 项 document.cookie 不可见，或信任判定在更深层。

#### ⑤ 未来解决方向（按性价比排序）
- **A. 补收 HttpOnly cookie**：挑战通过后的完整 cookie 状态里 odin_tt（可能还有别的）是 HttpOnly，document.cookie 不可见。下一步=用 **WKHTTPCookieStore 私有 API**（tvOS 上同样走 shim：NSClassFromString("WKWebsiteDataStore") → default → httpCookieStore → getAllCookies，全部经 objc_msgSend）收割 HttpOnly 全量，再测 post/mix。成本低、逻辑顺（就差最后一块 cookie）。⚠️ odin_tt 若仍不可见，把 WebView 里的请求代理出去（evaluateJavaScript fetch 同源 API）——WebView 内直接打 aweme/post 也是一条未经测试的路！
- **B. myDV 安卓真机抓包对照**：拿一台真机跑 myDV 抓 aweme/post 的完整请求（cookie/头/参数逐字节对比），终结"还有什么差异"的猜测。成本中等，信息量最大。
- **C. myDV 版本时效验证**：myDV v2.3.45 是旧版——抖音风控规则随时会变，先用最新 myDV 安卓包确认它的作品/合集**今天**还能不能用（用户口述为几个月前的体验）。
- **D. 扫码登录**（已批准路线 v2-v8）：登录 cookie 直接越过整堵墙，顺带解锁高清/收藏/关注流。工作量最大但一步到位。
- **E. series 短剧路线**：series/list 全通——若作者有短剧（series_infos 非空），短剧内容走 series/aweme（series_id 真值待测）。合集（mix）与短剧（series）是两套 id，别混。
- **探针资产**（全部可复跑）：`_tmp/round3_probe.js`（mssdk）/`round5/6/7/8_probe.js`（头/引导/矩阵）/`post_matrix_probe.js`（签名矩阵）/`uifid_probe.js`（cookie 罐）/`offset_type_probe.js`/`gen_mssdk_swift.js`（常量提取器）。

### 5.4 评论功能增强（次要）
- 当前固定取 3 页 60 条；滚动到底自动加载更多（cursor 分页已支持，加个触底加载即可）。
- 评论回复（reply_comment）、点赞等未做。

### 5.5 图集显示（价值中等，待用户决定）
- mobile proto 图片字段号未知、是否填充未证实；UI 方案已设计好（ImageCell 横滑 pager）；数据侧需 aweme 级 dump 探针。当前图集被 dur=0 信号过滤掉。

### 5.6 直播 / 登录（面板占位）
- 直播：myDV 有 LiveWebSocket（kq2.java webRid 弹幕）可参考，需直播间入口数据。
- 登录：扫码登录（网页套壳路线 v2-v8 已验证可行，被铁律限制为"仅登录用"）——登录后可解锁更清晰度/收藏同步。

## 6. 踩过的坑全集（按类别，务必牢记）

### 6.1 tvOS API 坑
1. `scrollToItem` 在 flow layout 未就绪时抛 NSException→SIGABRT（.ips 实锤）→ 用 clamp 的 `setContentOffset`。
2. `UICollectionView` 必须 `reloadData`（否则 numberOfItems 恒 0）。
3. `isPagingEnabled` 在 tvOS **不可用** → 用 `scrollViewWillEndDragging` 手动 snap。
4. tvOS blur 样式只有 `.regular/.prominent` 等老款——`systemThinMaterial/systemChromeMaterial` **unavailable in tvOS**（CI 实锤）。
5. `UIScrollView.isPagingEnabled`、`UIBlurEffect.system*` 之外：`playerPool.min` 返回 Optional 需解包。
6. tvOS 系统 Button 聚焦有灰色底板（`.plain` 也挡不住，tvOS 26 实锤）→ 自定义 `ButtonStyle`（label 原样返回）。
7. 子类实现父类 `required init` 写 `required` 不带 `override`（DanmakuKit example 同款）。
8. `AVPlayerItem.duration` 是属性不是方法；`item.tracks(withMediaType:)` 与属性 tracks 重载冲突（CI 实锤 "non-function type"）→ 用 `asset.loadTracks(withMediaType:)`。
9. `UIPanGestureRecognizer`/`UILongPressGestureRecognizer` 挂 controller.view 可接收 Siri Remote 触摸面触摸（触摸板手势的正确姿势）。
10. 跨文件类型 `private` 不可见（PanelRowButtonStyle 实锤）→ 改 internal。

### 6.2 Swift/编译坑
1. 大段重写类会**覆盖此前的小修复**——v143/v144 两次返工（var railLikeIcon、bind 方法丢失）。**重写后必须 diff 检查历史修复点。**
2. 编辑残留孤儿代码块（旧方法尾巴没删净）→ 编译失败；提交前自查。
3. KVO 闭包内 `item` 被外层循环变量遮蔽 → 用 `observedItem`/`playerItem` 无歧义名。
4. `required init` 子类实现写 `required` 不带 `override`。
5. `AnyTransition.scale` 参数名是 `scale` 非 `scaleEffect`；`OSAtomicIncrement32` 新 SDK 移除 → NSLock。
6. PowerShell 编码坑：inline `-Command` 写中文会 mojibake（用 Edit/Write 工具写文件）；`??` 是 PS7 语法 PS5.1 不支持；here-string 内联会炸；`>` 会被 cmd 当重定向吃掉。
7. 属性重命名后引用未跟上（commentAwemeId→awemeId 实锤）——改名后全局搜索旧名。

### 6.3 CI/流程坑
1. CI success 但下载/解压瞬态失败 → `dy_download.ps1 -ArtifactId <id>` 单独重下，**别重跑 pipeline**（双重 push）。
2. `dy_collector.ps1` 不常驻；启动会重置日志文件；离线期 ATV 连接堆积 → 恢复时 N 条连接各回灌 500 行缓冲（日志 92% 重复，分析前去重，`_tmp/analyze3_v128.ps1` 有现成逻辑）。
3. 大响应 `curl` 56 截断（分块发送已处理）。
4. CommitMsg 别带括号/特殊字符（cmd 转义坑）。
5. 后台跑 pipeline 超 320s 会转后台任务——轮询其输出文件，别重跑。

### 6.4 数据/字段坑（详见 §7 权威表）
1. **mobile proto 与 web JSON 字段号不通用**——拿 JSON 序号套 proto 必错（BitRate/awemeType/desc 三次栽过）。
2. field 21（video）= URL 生成时间戳 varint，非 bit_rate（epoch 解码实锤）。
3. f22（video）= 标志位非时长（曾污染 dur 取值链）；时长 = f13（实证 ms）→ f12 → f32。
4. awemeType 在 mobile proto 探 {43,55,61} 但对图集返回 0/缺失——**awemeType 过滤实际无效**，dur=0 才是可用的无轨信号。
5. desc=f2（含内联话题）、纯话题行=f459、省=f279、author f4（f3=昵称、f191=sec_uid、f2=uid 数字）、statistics=f10（f3赞 f2评 f6享 f11藏 f5播）、mix 候选=f14（f5=合集名、**f6=mix_id**）——**全部 wire 实测**。
6. `authentication_token` mobile proto 无此字段且**传空能通**（弹幕/评论均验证）。
7. **danmaku get_v2 服务端单请求最多回 ~25-30s 数据**（start_time 起算，end_time 超出被忽略）——分段窗口必须 ≤20s，60s 窗口会静默丢后半段（v151 实锤）。验收接口完整性必须对比小窗口全量条数，不能只看"比上一版多"。
8. **web 接口风控分层（v153-v162 实锤）**：tab-feed/comment/profile 宽松（假 msToken+最小头即可）；aweme/post、mix/aweme 严格（信任 cookie 也不够，见 §5.3）。**⚠️ 绝对不要给这条链加 sec-ch-ua/sec-fetch-* 等浏览器一致性头——头声称"我是浏览器"但 URLSession 指纹不是浏览器=自相矛盾，会把原本能过的接口也打挂（v157 真机回归实锤）。myDV 用 OkHttp 发这些头能过，平台不同结论不同。**
9. **jsvmp 反爬挑战页**：纯 HTTP 栈（Node/iOS URLSession）拉抖音首页 100% 被拦（72914 字节空 body JS VM 页，特征 `_$jsvmprt`/`__ac_signature`）——信任 cookie（s_v_web_id 等）只能由挑战页 JS 种下。绕过=隐形 WebView 引导（v161）。
10. **tvOS 无公开 WebKit 模块**（CI 实锤 `unable to resolve WebKit`）——用 WebView 只能走私有 shim：dlopen("/System/Library/Frameworks/WebKit.framework/WebKit") + NSClassFromString("WKWebView") + objc_msgSend（CGRect 必须 .m 桥），三件套在 v8 commit 77447bc 可恢复（Shim.h/.m + 桥接头 + project.yml SWIFT_OBJC_BRIDGING_HEADER）。

### 6.5 架构/流程坑
1. 同一路线连败 3+ 版 → 果断回退稳定底座，别让用户连续当测试员。
2. 改代码前必读实际文件+反编译（凭记忆=幻觉）。
3. `exit(0)` sideload 可用（设置面板 menu#2 退出）。
4. tvOS 焦点链：面板/列表打开时按键走 SwiftUI（onExitCommand/按钮），VC.pressesBegan 收不到——两套面板的按键处理必须各自实现，且互不干扰（焦点链隔离是特性不是 bug）。
5. 大响应/多连接的日志重复问题——分析前按行去重。
6. **串行队列内联回调 + 同队列 queue.sync = 自等待死锁（v147/v148 评论「闪退」真根因，v148 焦点理论被真机证伪）**：ttwid 已缓存时 ensureTTWID 的 done() 在 danmaku 队列内联执行，DYCommentClient.fetchPages 在同队列调 ttwidValue（queue.sync）→ 队列永久卡死 → 主线程的 ttwidValue（DYFeedClient 翻页/PlayerManager 播放头）跟着卡死 → 应用冻结被杀。日志特征：CMT 请求一行都没出现 + 操作后不久 ROOT auto-start。修复=跨模块回调永远先 DispatchQueue.main.async 跳出工作队列。焦点兜底（可聚焦元素/Button）仍是有益实践，但不是本例根因。
7. **两倍速触发方式最终定版（v156，用户多次实测触摸悬停不稳定后拍板）=长按确认键 0.6s 触发、松开恢复、短按呼出快捷面板**（pressesBegan 起 Timer / pressesEnded 判定短按或恢复 / pressesCancelled 兜底）。历程：v146 触摸长按 1.5s → v148 确认键 → v149-v155 触摸多通道反复调（LongPress 被默认互斥规则强杀是真凶之一；共存委托后偶发可触发但**始终不稳定**）→ v156 正式弃用触摸悬停，逻辑删干净避免与滑动冲突。**教训：触摸悬停方案在 Siri Remote 上试了 10 个版本始终不稳定，按钮方案才是可靠解**。

## 7. 数据字段权威表（全部 wire/探针实测，禁止猜测）

### 7.1 mobile `/aweme/v2/feed/` protobuf（Proto 解码）
| 层级 | 字段 | 语义 |
|---|---|---|
| root | f1/f2 | status_code / msg |
| root | f5 | aweme_list（bytes 数组） |
| root | f4 | has_more |
| aweme | f1 | aweme_id (str) |
| aweme | f2 | **desc 标题文案**（含内联话题） |
| aweme | f4/f5 | author / 原声 music author |
| aweme | f7/f8 | video（f8=play_addr_265/download_addr 家族） |
| aweme | f10 | **statistics**（f3=digg f2=comment f6=share f11=collect f5=play） |
| aweme | f14 | **mix/合集候选**（子消息，f5=合集名）——存在即合集 |
| aweme | f16 | create_time (秒) |
| aweme | f43/55/61 | awemeType 探测位（实测对图集返回 0/缺失——**不可用作过滤**） |
| aweme | f459 | **纯话题行**（"#a #b"，desc 去重用） |
| author(f4) | f1/f2 | uid (str) / uid 数字 |
| author(f4) | f3 | 昵称 |
| author(f4) | f5/f6/f7 | 头像（PlayAddr 同构，url_list 取第一个） |
| author(f4) | f191 | **sec_uid**（MS4wLjAB... 76B） |
| video(f7/8) | f1/f9 | **play_addr**（无水印播放版） |
| video(f7/8) | f8 | **play_addr_265/download_addr**（f8 实测=水印版，路径带 /video/cn/mps/logo/） |
| video | f3/f4 | width/height |
| video | f13 | **duration ms**（f12/f32 兜底；f22=标志位非时长） |
| video | f21 | URL 生成时间戳 varint（非码率！） |
| play_addr | f2 | url_list（s13.a：f2→递归→f1） |

### 7.2 web 端点（全部探针/真机实测；"严格链"=需要 uifid+x-secsdk 签名+信任 cookie 的端点，配方见 §5.3②）
| 端点 | 关键参数 | 状态 |
|---|---|---|
| `/aweme/v1/web/tab/feed/` | b0 配方 + webCommon；**响应 Set-Cookie 下发 UIFID_TEMP**（严格链的钥匙） | ✅ 双源已用 |
| `/aweme/v1/web/danmaku/get_v2/` | u11.K 参数 + webCommon；**20s 分段**（服务端单响应上限 ~30s 数据）；offset_time(ms)/text | ✅ 已用 |
| `/aweme/v1/web/comment/list/` | aweme_id/cursor/count=20；假 msToken 可用 | ✅ v147 已用 |
| `/aweme/v1/web/user/profile/other/` | sec_user_id/publish_video_strategy_type/source（严格链签名） | ✅ 匿名全通（v153 起真机） |
| `/aweme/v1/web/aweme/post/` | sec_user_id/count/max_cursor/need_time_list/from_user_page + version 290100（u11:3683 原样） | ❌ **签名过但 200 空静默拒绝**（详见 §5.3） |
| `/aweme/v1/web/series/list/` | sec_user_id/count/cursor（作者合集列表，字段 series_infos） | ✅ 探针全通（样本作者无数据） |
| `/aweme/v1/web/series/aweme/` | series_id/pull_type=2/source/count/cursor | ❌ mix_id 传入 sc=5（真 series_id 未测） |
| `/aweme/v1/web/aweme/detail/` | aweme_id/request_source=600/origin_type=quick_player | ✅ 探针全通 |
| `/aweme/v1/web/mix/aweme/` | mix_id/cursor/count | ❌ sc=4 参数错（myDV 也没实际调用它） |
| `/aweme/v1/web/mix/detail/` | mix_id | ⚠️ sc=0 但 mix_info 空 |
| `/aweme/v1/web/mix/listcollection/` | cursor/count | ❌ UIFID 墙（myDV 源码同标 blocked） |
| ttwid 注册 | POST ttwid.bytedance.com/ttwid/union/register/（body/headers u11.A 原文） | ✅ 匿名可用 |
| 首页引导 | GET www.douyin.com/?recommend=1 **5 跳重定向**（⚠️jsvmp 挑战页拦纯 HTTP 栈，需 WebView 引导 v161） | ⚠️ WebView 收割成功 |
| mssdk | POST mssdk.bytedance.com/web/r/token（u11:729 strData 常量，DYMsSdk.swift） | ⚠️ 换到真 msToken 但对 post 无帮助；真机 MISS |
| webCommon（必需） | device_platform=webapp&aid=6383&channel=channel_pc_web&cookie_enabled=true&browser_* | 缺则 "AppId不合法" |
| 签名 | getABogus(query,data,path,webUA) + timestamp 参数；a_bogus 后置 | ✅ 评论/弹幕/tab feed 全验证 |

## 8. 未来开发方向（路线图）

### 8.1 短期（体验收尾）
1. **新视频卡顿**：按 §5.1 组合 A+B+D 实施（等用户拍板）。
2. **弹幕重启**：按 §5.2 疑点顺序排查（offset_time 语义 → 轨道时序 → 时序对齐），数据说话。
3. **评论滚动加载更多**：cursor 分页已支持，触底加载 + "加载更多"按钮。
4. **悬浮窗补暂停/播放项**（OK 键被占用后暂停功能缺口）。

### 8.2 中期（功能扩展）
1. **作者作品列表**：按 §5.3⑤ 方向 A（WKHTTPCookieStore 私有收割 HttpOnly cookie）或 B（myDV 真机抓包对照）先解锁数据，再上作品屏（封面网格+点击播放，复用 merge 管道）。**⚠️ 禁止再给这条链加浏览器一致性头（v157 回归教训）**。
2. **合集/短剧浏览**：series/list 已通（作者合集列表）→ 有数据的作者直接接 UI；合集内容等 §5.3 数据解锁（或短剧 series_id 路线）。
3. **搜索**：顶部搜索条 UI + web 搜索端点（myDV 有 search/single 端点参照）。
4. **扫码登录**：解锁登录态（作品/合集/高清/收藏/关注流一步到位）——§5.3 若走到方向 D 就是它；网页套壳路线 v2-v8 已验证可行（铁律允许仅登录用 WebView）。
5. **直播**：myDV LiveWebSocket（kq2.java webRid 弹幕）参照，需直播间入口数据。

### 8.3 长期（打磨）
1. UI 美化统一轮：启动 spinner（v76 曾有）、弹幕样式设置、主题。
2. 弹幕设置项扩展（密度/字号/速度/透明度）。
3. 设置面板持久化扩展（各项 UserDefaults）。
4. App 图标（actool Assets.car 问题未解，已搁置）。

## 9. 关键文件
- `NativePlayerView.swift`：播放层全部（池/看门狗/手势/进度条/PC UI/PlayerCell）。
- `DYFeedClient.swift`：双源数据 + 解析（Proto 解码/选链/过滤/信息提取/stripInlineTopics）。
- `PlaybackEngine.swift`：引擎状态（urls/infos/durations/rawVideos/redirectUrls + reset/merge；DYVideoInfo 含 secUid）。
- `DYDanmakuClient.swift`（20s 窗口分段）/ `DYDanmakuOverlay.swift`（canShoot 门控发射器+自愈）/ DanmakuKit vendor。
- `DYCommentClient.swift`：评论数据。
- `DYProfileClient.swift`：**作者资料 + 作品/合集身份链**（cookie 罐/UIFID_TEMP/x-secsdk MD5/缓存节流重试）——§5.3 的主战场。
- `DYWebViewBootstrap.swift`：隐形 WebView 引导（shim 版，document.cookie 收割）。
- `DYWebViewShim.h/.m` + `DYTV-Bridging-Header.h`：私有 WebKit 桥（dlopen + objc_msgSend，v8 原件恢复）。
- `DYMsSdk.swift`：mssdk 真 msToken（strData 常量程序化提取自 u11:729，当前撤出主流程备查）。
- `DYQuickPanel.swift`：快捷悬浮窗 + 评论屏 + 作者主页屏（SwiftUI）。
- `DYSettingsModel.swift`：设置面板 + 快捷面板模型（SwiftUI）。
- `DYSigner.swift`：4 参 a_bogus 签名（JavaScriptCore + Signer JS 资产）。
- `DYLog.swift`：日志 + LAN 服务器（/log /stat /ping /clear）+ count()/event()。
- `HANDOVER.md`（本文档）、`MYDV_FEED_BLUEPRINT.md`（数据蓝图）、记忆文件 `dytv-*-*.md`。
- 探针（作品/合集攻坚线）：`_tmp/round3_probe.js`（mssdk）、`round5_probe.js`（全套头）、`round6_probe.js`（series/aweme）、`round7_probe.js`（series/list）、`round8_probe.js`（z() 引导）、`post_matrix_probe.js`（签名矩阵）、`uifid_probe.js`（cookie 罐）、`mobile_post_probe.js`（mobile 作品端点）、`offset_type_probe.js`（offset_time 类型）、`gen_mssdk_swift.js`（DYMsSdk 常量提取器）。
- 探针（弹幕/通用）：`_tmp/danmaku_probe.js`、`webfeed_probe.js`、`danmaku_hist_probe.js`、`danmaku_segment_probe.js`、`comment_works_probe.js`、`aweme_fields_probe.js`。
- 反编译：`_apk_work/jadx_out_classes/sources/defpackage/u11.java`（API 总集+签名链 i()/G0/rz0）+ `sl4.java`（cookie 罐）+ `jadx_ui_out/sources/defpackage/`（**UI 层，classes2/3.dex，146 类**：ProfileViewModel=ux3/nx3、WidgetRefresher）+ `com/github/mytv/dv/model/`（JSON 模型）+ `s13`（jadx_out，protobuf 解析权威）。
- **⚠️ 反编译注意：APK 有 3 个 dex，`jadx_out_classes` 只含 classes.dex——UI 层在 `jadx_ui_out`（classes2/3.dex，本会话才补齐）。**

## 10. 给下一个 AI 的明确指令
1. **先读本文档 §7 权威表 + §5.3 攻坚记录 + 实际代码 + 反编译**，禁止凭记忆/猜测。
2. **数据获取类改动：先开发机 Node 探针验证**（`_tmp/*probe.js` 复用），数据说话再进真机。
3. **治播放/数据 bug 先问 myDV 原项目**（u11.java = DouyinDirectApi 全集；UI 层在 jadx_ui_out——**APK 有 3 个 dex，别只反编译一个**）。
4. **同一路线连败 3+ 版 → 回退稳定底座**（当前 v122/v156），别让用户连续当测试员。
5. **大段重写后必须 diff 检查历史修复点**（v143/v144 两次返工教训）。
6. **CI/日志/编译的坑先查 §6**，已知问题别再踩一遍。
7. 每版交付后更新本文档 + 记忆文件；版本号 +1 禁止重复。
8. **作品/合集攻坚（§5.3）接手须知**：签名链/引导/WebView 已全部就位，别重造；下一步=方向 A（私有收割 HttpOnly）或 B（myDV 真机抓包）；**这条链永远用最小头，禁加浏览器一致性头**；触摸悬停已判死别再碰。
