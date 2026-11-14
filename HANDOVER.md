# DYTV 交接文档（v124 状态 · 2026-11-14）

> 本文档取代此前所有过时交接。所有结论均基于工具读取的实际代码与日志，非记忆。
> 当前版本 **v124**。**跳多页、声画不同步、冻屏已修复**；**黑屏（有声/无声）未解决**，是唯一遗留问题。

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

## 3. 当前架构（v124 实际状态）

- **数据层** `DYFeedClient`：移动端 `aweme.snssdk.com/aweme/v2/feed/` protobuf 直连。`DYSigner` 用 JavaScriptCore 跑 abogus.js 算 4 参签名。响应 protobuf 手工 wire 解码（`Proto` struct）。零 WebView。
- **播放层** `NativePlayerView`：UICollectionView 垂直分页 + PlayerManager 上限 3 池（current±1）。
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

## 5. 未解决问题：黑屏（有声/无声）——唯一遗留

### 5.1 现象
- **黑屏有声**：有声音、没画面。频次中等。
- **黑屏无声**：既无声音也无画面。较少。

### 5.2 根因诊断（v124 CODEC 诊断实锤）
- 可播视频编码 **全是 `avc1`(H.264)**，无 hvc1(HEVC) → **黑屏不是 HEVC 解不出**（推翻早期假设）。
- idx=31 出现 `codec=no-video-track` 但仍 `MGR ready` → **无视频轨的视频没被跳过**（图集/纯音频帖）。
- 看门狗抓到的黑屏是 `status=0`(`.idle`)、`t=0.0` → **player 压根没起来**（URL 无效/过期/无权限），看门狗能跳过这类。

### 5.3 根本困境
**移动端 protobuf 没有 bit_rate 子消息、没有 is_h265 字段**（video-dump 实锤：field21=单 varint 码率）→ **无法在 parse 阶段预判坏视频**，只能在播放时实测。而"播放时跳过"用 `centeredIndex()` 反推会跳多页，用 `engine.next()` 又要防级联——反复横跳。

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

## 8. 黑屏问题的下一步建议（未验证，需决策）

**推荐：播放时用 `currentItem.tracks(video)` 查视频轨 + 看门狗兜底（双层）**
- `readyToPlay` 时用 **`currentItem.tracks(video)`**（不是之前误判的 `asset.tracks`）查视频轨，空则跳过 → 治"无视频轨"黑屏。
- 看门狗（已有）兜底"有轨但时间不走"的黑屏 → 治"player 停 idle"。
- **风险**：`currentItem.tracks` 也有异步时序，需实测确认在 readyToPlay 后已加载完（v119 用 asset.tracks 误判过）。
- **先小范围验证**：加日志确认 `currentItem.tracks(video)` 在 readyToPlay 后是否稳定非空，再决定是否用它做跳过判据。

**备选**：若双层仍不理想，考虑集成 libVLC 软解（能解 HEVC），但违背"原生 AVPlayer"铁律 + 包体积暴涨 + 滑动重做，需拍板。

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
