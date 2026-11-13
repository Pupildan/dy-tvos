# DYTV 交接文档（v88 状态 · 2026-11-13）

> 本文档取代此前所有过时交接。当前代码已从「WebView 数据泵 + 单 AVPlayer」演进到「myDV 移动端 protobuf 直连 + UICollectionView 垂直分页 + PlayerPool」。所有结论均基于工具读取的实际代码，非记忆。请以本文档为准。

## 1. 项目背景与终极目标
纯原生 tvOS 抖音客户端，**绝对不使用 WebView 作为 UI**。完全原生 AVPlayer + 原生焦点遥控器控制。追求无限向下刷新（不卡 42 条）。

## 2. 环境与构建约束（极重要）
- **开发机 Windows，无 Xcode、无本地模拟器** → 无法本地编译，一切靠真机 + CI。
- **构建**：GitHub Actions（`CODE_SIGNING_ALLOWED=NO` 仅编译）。流水线 `_tools/dy_pipeline.ps1 -Version vX` 一条龙 commit→push→盯 CI→下载未签名 ipa 到 `output/`。
- **签名推送**：本地 Docker/AltStore 自签推 ATV，**7 天过期**。
- **版本号**：`DYBuild.version` 每次 +1，禁止重复（一版本号 = 唯一构建产物）。
- **ATV 崩溃拿不到堆栈**：原生崩溃不经过日志服务器，`output/atv_push.log` 只能看到崩溃前最后的自定义日志。诊断靠「分步日志 + 二分排除」，别指望崩溃堆栈。
- **反编译产物**：`_apk_work/jadx_out_classes/sources`（多数类）、`_apk_work/jadx_out/sources`（s13.java、highestQuality 比较器 lambda）。文件名带 `$` 时 PowerShell 通配失效，用 `cmd /c dir /s /b | findstr` 定位。

## 3. 当前架构（v88 实际状态，已用工具确认）
- **数据层** `DYFeedClient`：直连移动端 `https://aweme.snssdk.com/aweme/v2/feed/`。`DYSigner` 用 JavaScriptCore 跑 myDV 的 abogus.js 算 **4 参签名** `getABogus(query, data, path, ua)`。响应是 **protobuf 非 JSON**，`Proto` struct 手工 wire 解码。零 WebView。
- **播放层** `NativePlayerView`：`UICollectionView` 垂直分页 + **3 实例 `AVPlayer` 池**（`playerPool`/`playerIndex`/`PlayerLayerView`/`PlayerCell`）。真实视频图层随 Cell 滑动（UIScrollView 原生物理/惯性）。
- **启动动画**：`launch_video.mp4`（bundle，8.3MB）全屏循环静音播放，feed 首批就绪后淡出。**当前 `RootView.showLaunchVideo = false` 已禁用**（疑似导致启动闪退，见未解决 6.2）。

## 4. 踩过的坑（极其重要，血泪教训）

### 数据层
- **feed 端点**：必须用移动端 `aweme/v2/feed/`（host `aweme.snssdk.com`）。网页版 `tab/feed`、`module/feed` 池子小会卡 42 条。
- **签名 4 参**：`getABogus(query, data, path, ua)`，第 4 参 ua = 移动端 UA `com.ss.android.ugc.aweme/391000 (Linux; U; Android 16; zh_CN; Pixel 10 Pro)`。`DYSigner.sign(query:data:path:ua:)` + `navigator.userAgent` 运行时同步。
- **响应是 protobuf 非 JSON**：`s13.f()` 首字节 `==123('{')` 就 throw。必须手工 wire 解码（`Proto` struct）。字段：根 5=aweme 列表、1=status_code；aweme 7/8=video；video 1/9=play_addr；**play_addr field 2=真正 http CDN URL（field 1 是 uri 不可播）**，urlList 提取优先级 field 2→递归→field 1（`Proto.urlList`）。
- **移动端 bit_rate field 21 是 varint 非 bytes**（QDIAG 实测 f21=0），别硬套网页版 s13。暂用 play_addr field 8 直连已够。
- **最高画质**：`pickHighestQuality` 照 `highestQualityBitRate`（DataModelKt:155）——过滤 urlList 非空，按 h*w→fps→encodingScore(H265=1)→bitRateValue→gearName(≠adapt_lowest) 取最大。
- **403**：必须 1:1 补齐 Referer/Cookie/uifid/x-secsdk-csrf-token 等鉴权头。

### 播放层（双播放器池路线已证伪并废弃）
- **双 AVPlayerLayer 池（v71-v75、v79-v80 共 7 版）已放弃**：tvOS 上双全屏解码器 + CATransform/UIView transform 动画 + 预载/清空时序**天生脆弱**，反复黑屏/跳号/无声/闪退/Cannot Open。试过：裸 layer→容器 view→layoutIfNeeded→同 idx 不重载→loadingIndex+isKeepWorthy→错峰 clear，每轮只压下一个症状，黑屏/跳号/无声换马甲回来。**教训：双 AVPlayerLayer 池在 tvOS 是死路，别再试。**
- **UICollectionView 方案（v77/v78/v88）**：tvOS **无 `isPagingEnabled`**，需 `scrollViewWillEndDragging` 手动整页吸附；`scrollToItem` 在零 bounds 会崩（加 `bounds.height > 0` 守卫）；`playerPool.min` 返回可选需解包；`viewDidLayoutSubviews` 加零 bounds 守卫。这些都修过，v88 编译通过。
- **AVPlayerLayer 动画**：直接 `addSublayer` 到 view.layer 后动画 transform，真机不可靠，需套容器 UIView 动画 container.transform（v72 教训）。
- **首条 URL 失效**：douyinvod 直链有时效，播 14 秒可能 `Cannot Open`。`onFailed` **只走 `advance()`** 推进，绝不再调 `reportFailure()`（它会 triggerRefresh → 又动 index → 跳号 0→1→3）。
- **跳号**：slot 的 `statusObservation`(.failed) 和 `endObserver`(播完) 可能都 fire `onFailed` → 双 advance → 跳号。用 `didFail` 标志防同槽重复推进，`clear()` 重置。
- **声画同步**：滑动起步瞬间就 `outgoing.isMuted=true` + 新槽出声，不等动画完成。

### 启动黑屏
- 根因：`reloadIfNeeded` 守卫 `engine.index != currentIndex`，首批时 index=0/currentIndex=0 → `0!=0` 恒假 → 直接 return，activeSlot 从没装载首条 → 黑屏，按键才加载。
- 修：加 `hasLoadedOnce` 标志，首批到达**强制装载 index 0** 并播放。

## 5. 项目约束（必须永久遵守）
- **绝对不使用 WebView 作为 UI**。
- **绝对禁止造轮子**（用户原话）：未知字段/解析/清晰度选择不准猜或试探，必须去反编译项目（`jadx_out_classes`）找 myDV 现成源码 1:1 照抄再翻 Swift。
- 原项目同时有移动端和 PC 端，**当前只做移动端**数据获取+播放。
- 版本号每次 +1，禁止重复。
- **改代码前先用工具读实际文件**（血泪教训：v79-v88 十版凭记忆打补丁、old_string 反复不匹配、同症状反复 = 幻觉，用户点名批评「你出现幻觉了」）。
- **同一路线连败 3+ 版 → 果断回退稳定底座**，别让用户连续当测试员。

## 6. 未解决问题 + 解决思路

### 6.1 滑动连贯性/卡顿（当前核心卡点）
- **现状**：v88 UICollectionView 方案编译通过、能跑，但切换仍有卡顿/黑帧，老视频滑动观感不足。
- **可能原因**：`cellForItemAt` 里同步 `acquirePlayer`+`load`（建 AVAsset/item）在滑动时才建解码器；相邻预载时机偏晚。
- **解决思路**：① 滑动前预载目标±1 的 player（`preloadAdjacent` 已加，验证效果）；② 确保 `playerView.frame` 在 `willDisplay`/`layoutSubviews` 都刷新；③ 若仍卡，调低 `preferredForwardBufferDuration` 或提前 `loadValuesAsynchronously`。

### 6.2 启动闪退（疑似 launch_video，未确认）
- **现状**：v88 加 `launch_video.mp4` 后出现「打开就闪退」，崩在启动视频播放 + feed 同时启动。无崩溃堆栈。
- **二分**：RootView `showLaunchVideo = false` 已禁用启动视频。**下一步**：打包 v89 确认禁用后是否还闪退。
  - 不闪退 → 启动视频编解码器与 tvOS 不兼容 → 用 ffmpeg 转 H.264 baseline，或换成静态封面图。
  - 仍闪退 → 排除启动视频，问题在 feed/滑动逻辑，读分步日志定位。
- **拿崩溃堆栈**：ATV `~/Library/Logs/CrashReporter/DYTV-*.ips`（需在 ATV 上操作导出）。

### 6.3 任务 3 弹幕（未开始）
- 引入 DanmakuKit，数据获取严格照抄原项目（`u11.K()` 走 `/aweme/v2/web/danmaku/get_v2/`，需挖 DanmakuItem/DanmakuResponse 字段号，不猜）。
- `danmakuView.isUserInteractionEnabled = false` 不抢遥控焦点；`addPeriodicTimeObserver` 驱动；暂停弹幕暂停、快进清屏按新时间戳对齐。
- **前置**：滑动稳定后再做。注意弹幕是网页版路径（JSON DanmakuResponse/DanmakuItem snake_case），与移动端 protobuf feed 不同，需 web cookie。

### 6.4 可选后续
- 扫码登录拿真实 cookie（提升推荐质量）。
- mssdk msToken（现随机兜底够用）。
- 启动视频编解码兼容处理（若确认要做启动视频）。

## 7. 给下一个 AI 的明确指令
1. **先读实际代码再动手**（血泪教训：v79-v88 十版凭记忆打补丁 = 幻觉）。用工具读 `NativePlayerView.swift`/`DYFeedClient.swift` 实际状态。
2. **同一路线连败 3+ 版 → 果断回退稳定底座**，别让用户连续当测试员。
3. **tvOS 特殊性**（都是实测，不是猜）：无 `isPagingEnabled`、零 bounds 会崩、AVPlayerLayer 动画需容器 view、崩溃无堆栈。
4. 当前构建 v88，`showLaunchVideo=false`。**下一步优先**：打包 v89 确认禁用启动视频后是否还闪退（二分定位），稳定后调滑动连贯性。

## 8. 关键文件
- `NativePlayerView.swift`：UICollectionView 垂直分页 + PlayerPool（当前播放层）。
- `DYFeedClient.swift`：移动端 feed 直连 + protobuf 解码 + 最高画质。
- `DYSigner.swift`：4 参 a_bogus 签名（JavaScriptCore）。
- `PlaybackEngine.swift`：URL/索引状态管理。
- `LaunchVideoView.swift`：启动视频加载动画（当前禁用）。
- `MYDV_FEED_BLUEPRINT.md`：myDV 数据获取蓝图。
- `RootView.swift`：启动加载动画开关（`showLaunchVideo`）。
