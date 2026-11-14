# DYTV 交接文档（v129 无感过滤 · 2026-11-14）

> 本文档取代此前所有过时交接。所有结论均基于工具读取的实际代码与日志，非记忆。
> 稳定回退点仍是 **v122**（黑屏未达预期时 `git checkout` 回 v122 三文件即可）。
> **v128 = 残余黑屏攻坚版（真机验收通过，用户确认"体验有很大提升"）**：三靶点全过——真新鲜 URL（重定向链 100% 提取且 /aweme/v1/play 对未登录设备可用）、空轨检测、isReadyForDisplay 看门狗；15 分钟连刷 142 条，仅 2 个坏条目各 3-7s 自动治愈，0 级联 0 误杀 0 长黑屏。
> **v129 = 无感跳过图集/novideo（parse 阶段过滤，用户拍板）**：坏条目不进池，用户永远刷不到；runtime repair→skip 保留兜底。见 §11。
> **决策记录**：v111-v126 反复横跳后锁定 v122；v128 三个修复直指"从未被测过的洞"，与 v123-v127 的失败原因逐条对上（见 §8）。

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
