# DYTV 交接文档（v132 弹幕 · 2026-11-14）

> 本文档取代此前所有过时交接。所有结论均基于工具读取的实际代码与日志，非记忆。
> 稳定回退点仍是 **v122**（黑屏未达预期时 `git checkout` 回 v122 三文件即可）。
> **v128 真机验收通过（用户："体验有很大提升"）**：三靶点全过，0 级联 0 误杀。
> **v129 真机验收通过（用户："趋近完美"）**：parse 无感过滤（实际全靠 dur=0 信号；awemeType 信号在此 schema 无效）。
> **v130 真机验收通过（用户："确实提速了不少"）**：冷启动收敛 + idle 4s→2s。
> **v131 真机验收通过（用户："水印没了，播放体验趋于完美"）**：选链照抄 myDV（play_addr 优先 + selectBestPlayUrl 四级优先级），f8=download_addr 水印版降兜底。见 §13。
> **v132 = 弹幕功能上线（探针版）**：数据照抄 myDV u11.K/u11.A；渲染 vendor DanmakuKit(MIT)。见 §14。
> **决策记录**：v111-v126 反复横跳后锁定 v122；v128 三个修复直指"从未被测过的洞"（见 §8）。

---

## 1. 项目背景与铁律

纯原生 tvOS 抖音客户端。两条铁律：
1. **绝对不使用 WebView 作为 UI**。
2. **真实视频层滑动是核心体验，必须保留**（不能退回快照假滑动）。
3. **绝对禁止造轮子**：未知字段/解析/清晰度不准猜，必须翻反编译（`_apk_work/jadx_out_classes`）找 myDV 现成源码照抄。**v94-v99、v111-v124 反复因"造轮子/幻觉"翻车，这是最高教训。**

## 2. 环境与构建约束

- **开发机 Windows，无 Xcode** → 无法本地编译，全靠 GitHub Actions CI + 真机。
- 流水线 `_tools/dy_pipeline.ps1 -Version vX` 一条龙：commit→push→盯 CI→下载未签名 ipa 到 `output/`。
- 版本号 `DYBuild.version` 每次 +1，禁止重复。
- ATV 崩溃拿不到堆栈 → 靠"分步日志 + 二分排除"；**崩溃可隔空投送导出 `.ips` 读堆栈**（见 §7）。
- 日志：ATV 推送到开发机 `output/atv_push.log`（player 前缀 `MGR`/`CODEC`/`STALL`/`ENGINE`/`FEED`）。

## 3. 当前架构（v122 实际状态）

- **数据层** `DYFeedClient`：移动端 `aweme.snssdk.com/aweme/v2/feed/` protobuf 直连。`DYSigner` 用 JavaScriptCore 跑 abogus.js 算 4 参签名。响应 protobuf 手工 wire 解码（`Proto` struct）。零 WebView。
- **播放层** `NativePlayerView`：UICollectionView 垂直分页 + PlayerManager 上限 3 池（current±1）。
- **播放时现取新鲜 URL（v122 关键，治黑屏有声）**：`PlaybackEngine` 存每条 video 原始 bytes（`rawVideos[index]`），`acquire` 建 player 时用 `resolveFreshURL` 现跑 `pickHighestQuality` 取**当下新鲜 URL**，不用预载静态 URL（会过期→黑屏）。照 myDV `resolveFinalPlayUrl` 播放时现算模式。
- **跳多页已修**：删 `scrollViewDidEnd` 两委托（动画中途 `centeredIndex()` 反推致正反馈）、`advance/rewind` 直接 `engine.next()/prev()`、`scrollTo` 删 `for{next()}` 对齐循环。
- **声画不同步已修**：同上（不再有 skip 引发的换源错位）。
- **冻屏已修**：基本没有。

## 4. 已解决的问题（别再重复造）

| 问题 | 解法 | 版本 |
|---|---|---|
| 启动崩溃 `scrollToItem` 抛 NSException | 用 clamp 的 `setContentOffset` 替代；`UICollectionView` 必须 `reloadData` | v91/v92 |
| 跳多页 | 删 `scrollViewDidEnd` 两委托 + `advance` 直接 `engine.next()` + `scrollTo` 删对齐循环 | v115/v121 |
| 声画不同步 | 同上（不再有 skip 换源错位） | v121 |
| 冻屏 | 基本没有 | v108+ |
| **黑屏有声（大幅减少）** | **播放时现取新鲜 URL**（`resolveFreshURL`+`rawVideos`），不用预载过期静态 URL | **v122** |

## 5. 未解决问题：黑屏（有声/无声）——唯一遗留（v128 攻坚中）

### 5.1 现象（v122 真机实测）
- **黑屏有声**：有声音、没画面。**v122 已大幅减少**，但仍有残留。
- **黑屏无声**：既无声音也无画面。较少。

### 5.1a v128 攻坚（2026-11-14）——见 §8 三靶点 + §8.5 日志方法
- 真新鲜 URL（重定向）/ 空轨跳过 / isReadyForDisplay 看门狗，已过 CI 待真机验收。
- ⚠️ 重要证伪记录：v122 的"播放时现取新鲜 URL"**从未生效**（日志 381 次 fallback static / 0 次成功）——v122 黑屏减少另有原因或会话方差，勿再归功于该机制。
- ⚠️ field 21 语义修正：是 **URL 生成时刻的时间戳**（epoch 解码 1794753056=2026-11-14 22:30:56≈抓取时刻），不是码率（1.79e9 kbps 荒谬）。

### 5.2 根因诊断（v124 CODEC 诊断 + video-dump 实锤）
- 可播视频编码 **全是 `avc1`(H.264)**，无 hvc1(HEVC) → **黑屏不是 HEVC 解不出**（推翻早期 HEVC 假设，别再往解码方向猜）。
- **黑屏无声**：部分视频 `currentItem.tracks(video)` 为空（无视频轨，如图集/纯音频/无效媒体）→ player ready 但无画面。
- **黑屏有声**：player 停在 `.idle`（`status=0`、`t=0.0`）→ URL 无效/过期/无权限，拿不到可播媒体。

### 5.3 根本困境
**移动端 protobuf 没有 bit_rate 子消息、没有 is_h265 字段**（video-dump 实锤：field21=单 varint 码率）→ **无法在 parse 阶段预判坏视频**，只能在播放时实测。而"播放时跳过"用 `centeredIndex()` 反推会跳多页，用 `engine.next()` 又要防级联——反复横跳。

### 5.4 v122 已做的缓解 + 残余
- **黑屏有声（大幅减少）**：`resolveFreshURL` 播放时现取新鲜 URL（`rawVideos[index]` 现跑选链），不用预载过期静态 URL → `Cannot Open` 大幅减少。
- **残余黑屏有声**：仍有部分 URL 现取后仍无效（无权限/CDN 节点抖动），待定位。
- **黑屏无声**：无视频轨视频（`tracks(video)` 空）当前**不跳过**，会停在黑屏。**待办**：见 §8 双层检测方案。

## 6. 试过的方法（重点：哪些有效、哪些失败）

### 有效（保留在 v124）
- **`setContentOffset` 替代 `scrollToItem`**（后者 tvOS 抛 NSException）。
- **删 `scrollViewDidEnd` 两委托 + `advance` 直接 `engine.next()`** → 治跳多页。
- **黑屏看门狗**：每 1.5s 查居中 player 时间是否前进，连续 2 次停滞则 `advance()`。能抓"player 停在 idle"的黑屏。
- **CODEC 诊断**：KVO ready 时查 `currentItem.tracks(video)` 编码，确认非 HEVC。

### 失败/被否（别再重复）
- **双 player 池（v77-v83）**：黑屏/跳号/无声，全败，回退单 player。
- **`.failed → advance` 自动跳过（v111/v112）**：用 `centeredIndex()` 反推 → 跳多页 + 声画不同步，v121 删除。
- **按 URL 字样猜 HEVC（v98）**：URL 里无可靠编码标志，失败。
- **按 JSON 序号套 proto 字段号（v118 awemeType=field6）**：field6 非 awemeType，空操作。
- **`asset.tracks` 在 readyToPlay 查视频轨（v119）**：track 异步未加载完 → 误返回空 → 误杀好视频 → 黑屏无声增多，v120 删除。
- **`pickHighestQuality` 读 bit_rate（field21/31）**：移动端 field21 是单 varint 非 bytes，**恒返回 nil**，从没成功过。

## 7. 踩过的坑（血泪，务必牢记）

1. **tvOS `scrollToItem` 抛 NSException → SIGABRT**：flow layout 未就绪时调用会崩。用 clamp 的 `setContentOffset` 替代。
2. **`UICollectionView` 必须 `reloadData`**：否则 `numberOfItems` 恒 0 → scrollTo 全 SKIP → 黑屏。
3. **改代码前必读实际文件**：v79-v124 多版凭记忆打补丁 = 幻觉，被点名批评。**治播放 bug 先问 myDV 原项目怎么做。**
4. **同一路线连败 3+ 版 → 果断回退稳定底座**，别让用户连续当测试员（v94-99、v111-124 两次翻车）。
5. **myDV 手机端(protobuf) 与 PC端(JSON) 字段号不通用**：拿 JSON 序号套 proto 必错（BitRate/awemeType 都栽过）。
6. **AVPlayer 原生解 HEVC**（myDV VideoPlayUrlResolver 证明）→ 黑屏非 HEVC，别再往解码方向猜。
7. **`item` 变量遮蔽**：KVO 闭包内 `item` 易被外层 `enumerated()` 循环变量遮蔽，导致 `item.tracks` 编译错。用 `playerItem`/`observedItem` 等无歧义名。

## 8. v128 三靶点（2026-11-14 实施，基于实锤，与 v123-v127 失败原因逐条对上）

**已排除的方向（别再重复）**：HEVC（v124 全 avc1）、图集、解码器耗尽（v110）、CDN 域名（同域名 ok/FAIL 交错）。

**v128 为什么不是"第 4 次叠机制"——v123-v127 每次失败的具体原因这次都找到了**：
| 旧尝试 | 失败原因 | v128 对应修复 |
|---|---|---|
| v122 resolveFreshURL"存 bytes 现选" | **日志证伪：381 次 fallback static / 0 次成功**。pickHighestQuality 找 bytesFields(21/31) 恒 nil（field 21 是 varint 时间戳非 bit_rate 子消息）；且重解析旧 bytes 本身选不出新 URL（bytes 里只有同一批链接） | **真新鲜**：静态直链 age>90s 改用 `/aweme/v1/play/` 重定向端点（URL 不带时效签名，服务器请求时现场 302 出新鲜直链，AVPlayer 自动跟随）。照 myDV selectBestPlayUrl 第②优先级 |
| v123 停滞看门狗 | 盯"时间不前进"——黑屏**有声**时音频在走、时间在走，**永远不触发** | **isReadyForDisplay 看门狗**：ready+播放+时间走但首帧渲染不出 2s → 检出（myDV onRenderedFirstFrame 的 AVPlayer 等价信号） |
| v125 视频轨检测 | 编译失败（item 遮蔽）后陷入回退混乱，**从未真机验证**——不是方案被证伪 | **currentItem.tracks(.video) 空轨检测**：0.6s 复查防误杀，identity 守卫防旧 item 延迟回调误伤 |

**v128 统一动作阶梯**：检测命中 → 先 repair（换重定向直链就地重建，照 myDV onPlayerError 先重试）→ 仍异常才 skip。
**护栏**：只监控/跳过居中（index==engine.index）；连续自动跳 ≥3 停手（WATCH cascade-stop），手动按键复位；skip 用 engine.next()+显式 scrollTo，绝不用 centeredIndex 反推。
**检测三层**：idle（status 非 ready 连续 4s）/ stall（ready+非暂停+时间停滞 3s）/ black（ready+时间走+无首帧 2s）；novideo（tracks 空 0.6s 复查）。

**风险对冲**：静态直链优先（快启动、全清晰度），最坏情况=现状；redirect 端点若 403（无登录 cookie）只影响超龄条目，看门狗 repair/skip 兜底。

## 8.5 日志诊断方法（v128 升级——排障一次 curl 看全）

- `curl http://<ATV-IP>:8765/stat`：版本 + **计数器全量**（feed_page/feed_aweme/feed_usable/feed_redirect/url_static/url_redirect/acquire/ready/novideo/itemErr/repair/autoskip/scroll/cover_retry）+ **最近 15 条诊断事件环**（WATCH repair/skip、MGR itemErr/novideo、FEED 0 usable 等）+ 最近直链。
- `curl http://<ATV-IP>:8765/log`：末 50 行常规日志。`/ping`、`/clear` 保留。
- `DYLog.event()` = 常规日志 + 事件环双写；`DYLog.count(key, by:)` 计数器。新增诊断一律走这两个，别散落裸 log。
- FEED 每视频日志已压缩成 1 行：`FEED item a[i] id=.. type=.. static=ok/none redirect=ok/none dur=..`（旧 7 行 loop 噪音已删）；每页首条仍 dump video 全字段监控 schema 漂移。
- ⚠️ 运维：`dy_collector.ps1` 不会常驻——读日志前先 `netstat -ano | findstr :9988` 确认 LISTENING；采集器启动会重置日志文件；ATV 只在新日志行产生时才重连，采集器起来后需要用户操作一下 ATV 触发回灌；ATV IP 可从 netstat 9988 的 ESTABLISHED 远端拿。
- ⚠️ 已知缺陷（待优化）：采集器离线期间 ATV 堆积的 N 条连接恢复时各回灌一份 500 行缓冲 → 日志大量重复（分析前先按行去重，`_tmp/analyze3_v128.ps1` 有现成去重逻辑）；ATV :8765 /stat 入站 curl 可能不通（连接堆积），文件日志已够用。

## 11. v129 无感跳过图集/novideo（parse 阶段过滤，2026-11-14 用户拍板）

- **语义照抄** myDV `filterPrimaryPlayableAwemes`（DataModelKt.java:131，在 feed 响应处理处 zq5 调用）：awemeType==0 且 playAddr 非空才进池。
- **双信号实现**：① `awemeType != 0` —— 照 s13.e:371 依次探字段 {43,55,61}，第一个落在 [0,201) 的值即 type，全缺默认 0（=myDV 模型行为）；② `dur == 0` —— wire 实锤：v128 两个 novideo 坏条目（idx=69 id=7697175741067703211 / idx=82 id=7706360995123839439）的时长字段全缺。
- **dur 取值链修正**：f13（wire 实证=真实时长 ms）→ f12 → f32；f22 是标志位非时长（v128 取值链被它污染，26 条正常视频被误标 dur=1）。
- **过滤日志**：`FEED skip-item a[i] id=.. type=.. dur=.. reason=type|nodur`（事件环）；页统计行加 `filtered=N`；计数器 filter_type/filter_nodur。
- **runtime repair→skip 保留兜底**（极罕见 type=0 但媒体真坏）。
- **图集显示（暂缓，可行性已分析给用户）**：myDV 不做图集展示无参照；图片字段号未知、服务器是否填充未证实，需 aweme 级字段 dump 探针；UI 方案已设计好（ImageCell 横滑 pager + 左右键翻图/上下键切条，cell 不可聚焦按键集中在 pressesBegan，不碰滚动路径）。全会话 dur=0 仅 5/175（2.9%），价值中等。待用户决定。
- **v129 验收补充**：冷启动首帧实测 11s（17:44:04 启动→17:44:06 首页解析完→idx=0 静态直链 age=0 但 4s 不 ready→17:44:11 repair→17:44:15 ready）；两链都慢=网络首连/冷门 CDN 域名慢，非 URL 选择问题 → 催生 v130。

## 12. v130 冷启动首帧提速 + 坏链快速恢复（2026-11-14 用户拍板"其他的问题一次性解决"，UI 美化后期统一做）

- **冷启动收敛（PlayerManager.prepare）**：池全空（会话首个 prepare）→ 只 acquire 居中条且 `forceRedirect: true`（省掉静态直链 4s 空等 + repair 重建来回）；邻居 index 记入 `pendingNeighbors`，居中 ready 后 `drainPendingNeighbors()` 补装载（此时网络已暖，邻居仍走静态快启动）。规避启动瞬间 3 个并发 TLS 握手互拖（v129 idx=1 TLS error 实锤）。正常路径（池非空）行为与 v122 完全一致。
- **idle 看门狗 4s→2s**（watchIdleTicks）：repair 实测 1-2s 恢复，静态直链打不开少等 2s；stall=3s、black=2s 不动（stall 要区分正常缓冲）。
- **验收指标**：启动→首帧时长（v129 基线 11s，目标 ~6s）；`MGR cold-start defer/acquired` 日志；`cold_start` 计数器；TLS error 是否随并发收敛消失。
- **用户决定搁置**：启动 loading spinner 等 UI 美化（v76 曾有 spinner，v122 重构丢失）——待基础功能完美后统一做。

## 13. v131 去水印（2026-11-14 用户拍板）

- **根因**：抖音每条视频两份转码——play_addr（f1/f9，播放版**无水印**）+ download_addr（f8，下载版**烧录漂移水印**）。myDV 播放只从 play_addr 选（s13.e：f8 在其模型里就是 downloadAddr）；我们 v58 时代实测"f8 直连快"固定 8→1→9 选链 = 踩 download_addr。日志铁证：我们播放的 URL 路径带 `/video/cn/mps/logo/`（转码服务+水印模板）。
- **修复**（DYFeedClient.parse + 新增 selectBestPlayUrl/isPathSigned，均照抄 VideoPlayUrlResolver）：
  1. 候选 = play_addr（f1/f9）url_list（取第一个非空子消息，f1 优先 f9），空则退化 f8；
  2. 候选内四级优先级原样：① `douyinvod.com/[32hex]/[8hex]/` 签名直链 ② `douyin.com/aweme/v1/play` ③ douyinvod+`signature=` ④ 列表最后一个；
  3. v128 双链/age/repair 机制不动（redirect 取自 f1/9 本就是无水印家族）。
- **验收**：first url 路径形状（签名直链 = 快+无水印；若 f1/9 只有重定向 URL 则首播多一跳 302）；真机肉眼确认无水印；ready 率/首帧时长不得回退。
- **v131 验收结果（2026-11-14）**：用户确认"水印没了，播放体验趋于完美"。播放线（黑屏/跳页/无感过滤/水印/冷启动）全部收工。

## 14. v132 弹幕功能（2026-11-14 探针版，待真机验收）

**数据链（照抄 myDV 反编译）**：
- 请求：GET `https://www.douyin.com/aweme/v1/web/danmaku/get_v2/`，参数照抄 u11.K:1310（app_name=aweme/format=json/group_id/item_id/start_time=0/end_time/duration/authentication_token/pc_libra_divert=Windows/support_h265=0/support_dash=1/version_code=170400/version_name=17.4.0 + D0 公共参数）。
- 响应：JSON `{status_code, danmaku_list:[{danmaku_id, offset_time(ms), text, ...}]}`（DanmakuResponse/DanmakuItem.java 对应）。
- web 身份：Chrome 147 桌面 UA（u11.A 原文）+ **ttwid 匿名注册**（POST ttwid.bytedance.com/ttwid/union/register/，body/headers u11.A 原文，Set-Cookie 取 ttwid，存 UserDefaults dy_ttwid）+ Referer `https://www.douyin.com/video/<id>`。无需登录。
- 签名：web 链 myDV 用 generateABogusParam/G0（蓝本 §5）；v132 探针复用现有 4 参 getABogus（第 4 参传 web UA）+ timestamp 参数——可用性由 DANM 日志实锤。
- ⚠️ **已知未知数（探针中）**：authentication_token / group_id 的 mobile proto 字段号未知（s13.e 未映射）——aweme-dump 探针同跑；v132 先传 awemeId/空 token，若 status_code!=0 或 items=0 按日志定论。

**渲染（vendor DanmakuKit，MIT）**：
- `qyz777/DanmakuKit` core 源码 vendored 到 `App/Sources/DanmakuKit/`（LICENSE-DanmakuKit.txt 保留归属；未走 SPM——其 Package.swift 无 tvOS 平台声明；未用 fndanmu——用户明确其渲染不行）。
- 架构 = 业界成熟模式：**CABasicAnimation(position.x) 由 Core Animation 合成器驱动 + DanmakuAsyncLayer 异步位图绘制 + cell 复用池** → 滚屏流畅性由系统渲染管线保证。
- vendored 修补（v132）：Sentinel 的 OSAtomicIncrement32（已废弃/新 SDK 可能移除）→ NSLock 等价实现；其余 tvOS 兼容零改动（PlatformTypes.swift 已有 tvOS awareness，扫描无 iOS-only API）。
- 集成：`DYDanmakuOverlay`（PlayerCell 内，视频层之上/封面之下，isUserInteractionEnabled=false 焦点隔离）——DanmakuTextCellModel/DanmakuTextCell（黑描边白字）+ 按播放时钟发射器（0.25s tick，迟到 >2.5s 不补射）；参数 trackHeight=46/displayArea=0.55/速度 300px/s/字号 38。
- 播放同步：load(awemeId)（换片清屏重取）→ syncPlaying（居中在播=play+游标对齐）→ seekSync（清屏重对齐）→ toggle/seek/togglePlayPause 全接。
- 弹幕总开关 `DanmakuOverlay.enabled` 默认 true（UI 开关待美化阶段统一做）。
- 日志：DANM 前缀（get/ttwid/ok/status_code/http err）+ FEED aweme-dump（每页首条 aweme 级字段 dump）+ 计数器 dm_items/dm_shoot。
- **验收**：真机弹幕是否显示；DANM ok（status_code=0+items>0）还是被拒（token/签名/cookie 哪个缺失由日志定论）；滚屏流畅度。
- **v132 真机验收结果**：弹幕未显示，日志 `DANM status_code=3`（端点拒绝），渲染层就绪无报错。
- **⚠️ 开发机验证门（v133 起的重大流程升级，用户提议并采纳）**：数据获取类改动**先在开发机用 Node 复刻整条链验证**（`_tmp/danmaku_probe.js` 可复用：加载 Signer JS + protobuf 解码 + HTTP 矩阵），数据说话后再进真机代码——一轮脚本顶 3-4 轮 CI。

## 15. v133 弹幕数据链打通（2026-11-14，开发机探针定位根因，CI 过待真机验收）

- **v132 失败根因（开发机探针实锤）**：`status_msg="AppId不合法"`——弹幕请求缺 **web 公共参数**（`device_platform=webapp&aid=6383&channel=channel_pc_web&cookie_enabled=true&browser_*`）。myDV 的 u11.K 参数表本身就没有这些（myDV mobile 路径的弹幕链同样是坏的——tw0/rn5 的 token 非空门槛在 mobile proto 上永远不满足，它根本不会发请求）。
- **修复（DYDanmakuClient.fetch）**：参数表 = webCommon 前缀 + u11.K 参数 + D0 公共参数；**签名输入 = 完整 query 含 timestamp**（webCommon+dm+timestamp → getABogus(webUA) → a_bogus 后置）；authentication_token 传空（**开发机探针实锤：mobile proto 无此字段且空值能通**，aweme-dump 候选字段全是 JSON/URL/sec_uid 非 token）。
- **开发机探针实测**（`_tmp/danmaku_probe.js`）：status_code=0，12s 短视频 items=1461、186s 视频 items=817，连发 6 个无频控；弹幕数据 `danmaku_list[{offset_time, text, danmaku_id}]` 直连可用。
- **验收**：真机弹幕显示 + `DANM ok items=N` 日志 + 滚屏流畅度（DanmakuKit Core Animation 驱动）。
- 后续可选：弹幕开关 UI（enabled 属性已预留）、按 user_id 过滤、密度限制。

## 17. v135 设置面板 + 双视频源（2026-11-14 用户规格，CI 过待真机验收）

- **Menu 状态机**：面板关闭按 Menu → 呼出设置面板（DYPlayerViewController.pressesBegan 拦截 .menu）；面板显示中按 Menu → 退出应用（焦点在面板内走面板 `.onExitCommand` → `exit(0)`，sideload 可用）。
- **面板 UI**：屏幕左侧悬浮 SwiftUI；tvOS 26 原生 **Liquid Glass**（`.glassEffect(.regular.tint(.black.opacity(0.35)))`，Xcode 26.6 SDK 编译实锤存在；低版本 ultraThinMaterial 回退）。五项：移动端推荐 / 抖音精选 / 弹幕设置（开关，UserDefaults dy_danmaku_on + DanmakuOverlay.globalEnabled）/ 直播（占位）/ 登录（占位）。
- **抖音精选（web 源）**：GET `https://www.douyin.com/aweme/v1/web/tab/feed/`，b0 配方 u11.java:2701 参数原样 + webCommon（danmaku 探针实锤必需）+ web 签名 + ttwid cookie；**开发机探针（_tmp/webfeed_probe.js）已验证**：status_code=0、refresh_index 分页正常、JSON 含 play_addr/play_addr_265/bit_rate(8-24档) 全量数据；播放链复用 selectBestPlayUrl；播放请求头按源切换（PlayerManager.playbackHeaders：web=Chrome UA+Referer+ttwid）。
- **架构**：`DYFeedSource` 枚举 + `PlaybackEngine.reset()`（源切换清空）+ `DYFeedClient.setSource()`（重置分页状态）+ reloadIfNeeded 空态重置；源切换后池清空 → 冷启动收敛自动生效。
- **CI 踩坑**：ensureTTWID 私有重名 → 改 ensureTTWIDInternal。产物 output/DYTV-tvos-unsigned-v135.ipa。
- **真机验收**：Menu 呼出面板/再按退出；源切换到抖音精选后视频正常播放（web 直链 AVPlayer 播放是本版唯一未实测点——HEAD 403 是测试方法问题，真机 GET+带头待验）；弹幕开关即时生效。

## 16. v134 弹幕样式修正（2026-11-14 用户反馈：弹幕出现了但要改样式）

- ①去白底：根因 = DanmakuAsyncLayer 在 layer isOpaque==true 时主动填白（UIColor.white）；修 = DanmakuTextCell `required init(frame:)`（官方 example 同款写法）+ backgroundColor=.clear + isOpaque=false + layer.isOpaque=false。
- ②去描边：弹幕 JSON 无颜色字段（danmaku_type/score/text_extra，无 color），默认色即白 → 纯白字无 stroke。
- ③弹幕区域限定视频 aspectFit 内切矩形（用户：手机竖版源弹幕不该飘全屏黑边）：PlayerCell.updateDanmakuFrame() 用 presentationSize 算内切矩形（ready 后 presentationSize 才有效；bind/layoutSubviews/updatePlaybackStates/refreshCoverForVisible 四处触发）；滚屏时长按区域实际宽度算。
- CI 踩坑：子类实现父类 required init 要写 `required` 不带 override（官方 example 同款）；PlayerCell 里是 playerLayerView.player 不是 playerLayer。产物 output/DYTV-tvos-unsigned-v134.ipa。

## 9. 关键文件
- `NativePlayerView.swift`：播放层（UICollectionView + PlayerManager cap-3 池 + 黑屏看门狗 + CODEC 诊断）。
- `DYFeedClient.swift`：移动端 feed 直连 + protobuf 解码 + `pickHighestQuality`（恒 nil，待修）。
- `DYSigner.swift`：4 参 a_bogus 签名（JavaScriptCore）。
- `PlaybackEngine.swift`：URL/索引状态管理（含 `rawVideos` 存储）。
- `MYDV_FEED_BLUEPRINT.md`：myDV 数据获取蓝图。
- `output/atv_push.log`：真机日志（`MGR`/`CODEC`/`STALL`/`ENGINE`/`FEED` 前缀）。

## 10. 给下一个 AI 的明确指令
1. **先读实际代码再动手**（血泪：v79-v124 多版凭记忆打补丁 = 幻觉）。
2. **治播放 bug 先问 myDV 原项目怎么做**（`_apk_work/jadx_out_classes`），别自己造轮子。
3. **同一路线连败 3+ 版 → 回退稳定底座**（v121 是当前稳定点）。
4. **当前唯一遗留 = 黑屏**。建议先按 §8 用 `currentItem.tracks` + 看门狗双层验证，数据说话再深挖。
