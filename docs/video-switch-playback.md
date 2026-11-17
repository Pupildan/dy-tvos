# 抖音式垂直视频切换播放 —— 实现流程（可复用）

> 来源：DYTV tvOS 项目（SwiftUI + AVFoundation + AVKit）。
> 核心三文件：`PlaybackEngine.swift`（数据/状态）、`NativePlayerView.swift`（池+分页+手势+渲染，~1170 行）、`DYFeedClient.swift`（数据源）。
> 本文是**通用架构**，不含抖音特有逻辑（签名/数据源），可直接搬到别的项目。所有坑都是真机/CI 实锤。

---

## 一、整体架构（三层分离）

```
SwiftUI RootView
  └─ NativePlayerView (UIViewControllerRepresentable)
       └─ DYPlayerViewController
            ├─ UICollectionView (垂直分页, 一屏一 cell)
            │    └─ PlayerCell (playerLayerView + cover 兜底 + danmaku overlay)
            ├─ PlayerManager (AVPlayer 池, ±2 窗口)
            └─ PlaybackEngine (有序 URL 列表 + index + 翻页/刷新回调)
数据源: DYFeedClient → PlaybackEngine.merge()
```

**核心设计**：Cell **不创建也不持有** player，只有一个 `playerLayerView`（`AVPlayerLayer` 容器）。player 由 PlayerManager 池分配，`willDisplay` 时 `bind` 到 cell。这样滑动时 player 不随 cell 重建，滑动切房动画由 collection view 自己的滚动产生。

---

## 二、核心机制（按复用优先级）

### 1. 池窗口 + 驱逐（防解码器耗尽→黑屏）

`PlayerManager.prepare(center:)`：

- 维持 `[idx-2, idx+2]` 共 5 个 AVPlayer。
- **超范围立刻 `pause()` + `replaceCurrentItem(with: nil)`** —— 置空 item 让系统瞬间回收解码器（缺这步→解码器耗尽→黑屏）。
- **冷启动收敛**：池全空（首个 prepare）只装载居中条，邻居推迟到居中 ready 后 `drainPendingNeighbors` 补齐——避免启动瞬间 3 个并发 TLS 握手互相拖垮。
- `peekPlayer(at:)` 纯查询不 acquire——`willDisplay` 用它，防快速滑动把池撑大（抖动→黑屏）。
- 窗口别用 ±1：来回微抖会驱逐刚 ready 的→黑屏。±2 留缓冲余量。

### 2. Cell 渲染绑定 —— `willDisplay`

```
peekPlayer → 有就 cell.bind(player:)，ready 则隐藏封面、没 ready 显示封面兜底
           → 无条件 loadCover（否则预载就绪的视频永远拿不到封面→氛围层空白）
```

### 3. 垂直分页 + 滑动切换 —— 手势接管，不用 `isPagingEnabled`

- tvOS `isPagingEnabled` 不可用 → `scrollViewWillEndDragging` 手动 snap：
  `snappedY = (velocity≥0 ? ceil : floor)(targetY/pageHeight) * pageHeight`
- 关掉 collection 原生 pan，自己加 `UIPanGestureRecognizer`：位移 >100px 判定切换，`setTranslation(.zero)` 防连发。上滑=下一条。
- 遥控：`pressesBegan` 的 up/down 箭头 → `advance()/rewind()` → `scrollTo(animated:true)`。
- **切房用 `setContentOffset` 不用 `scrollToItem`**（后者 flow layout 未就绪抛 NSException→SIGABRT）。

### 4. 换房后对齐 + 播放 —— `scrollTo` → `updatePlaybackStates`

- scroll 停止（`scrollViewDidEndScrollingAnimation` / `DidEndDecelerating`）→ `updatePlaybackStates(center:)`：
  居中 cell `bind` + ready 则 `play()`，非居中 `pause()`；**只查池不触驱逐**（杜绝双 center 打架抖动）。
- 索引对齐引擎（唯一真相源），接近末尾 `triggerNeedMore()` 无限翻页。

### 5. 新建 player —— `acquire(index:)`

```
resolveFreshURL → AVURLAsset(url:, options:["AVURLAssetHTTPHeaderFieldsKey": headers])
              → AVPlayerItem(preferredForwardBufferDuration=8, audioTimePitchAlgorithm=.timeDomain)
              → AVPlayer.replaceCurrentItem
              → KVO item.status: ready→onPlayerReady+drainNeighbors; failed→只记日志(不自动跳)
```

- **URL 新鲜度**：静态直链 ≤90s 用静态，超龄走重定向端点（服务器现场 302 出新鲜直链）。
- **header 必带**：`AVURLAssetHTTPHeaderFieldsKey` 塞 Referer+UA（缺了 CDN 返回空→黑屏）。

### 6. 首帧信号 —— `playerLayer.isReadyForDisplay`

`watchTick`（1s 定时）查居中 cell 的 `playerLayer.isReadyForDisplay`——这是"首帧已渲染"的 AVPlayer 等价信号（对应 myDV `onRenderedFirstFrame`）。用于：启动加载视频淡出、看门狗黑屏判定。

### 7. 看门狗（防黑屏/卡住）

1s 心跳三层检测：
- `idle`：status 非 ready 持续
- `stall`：时间不走
- `black`：时间走但 `!isReadyForDisplay`
→ 修复或自动跳下一个。手动按键复位自动跳。

---

## 三、踩过的坑（复用时务必避开）

| 坑 | 后果 | 正解 |
|---|---|---|
| `scrollToItem` | flow layout 未就绪抛 NSException→SIGABRT | 用 clamp 的 `setContentOffset` |
| tvOS `isPagingEnabled` | 不可用 | 手动 snap（见 §3） |
| 池窗口太小(±1) | 来回微抖驱逐刚 ready 的→黑屏 | ±2 留缓冲余量 |
| `replaceCurrentItem(nil)` 缺失 | 解码器不回收→耗尽黑屏 | 驱逐必须置空 item |
| willDisplay 里 acquire | 快速滑动撑大池→抖动黑屏 | 只 `peekPlayer` |
| player 池 per-cell 各建 | 多 player 抢解码器→大部分黑屏 | 单池窗口分配 |
| 全屏分页器上叠可聚焦控件 | 焦点锁死、遥控键失效 | 删掉返回按钮等可聚焦控件 |
| 触摸悬停切换 | Siri Remote 试了 11 版全不稳 | 用长按确认键 / 纯滑动 |
| `AVPlayerItemDidPlayToEnd` 符号 | 部分 SDK 解析不到（`NSNotification.Name?` 无此成员） | 用 `NSNotification.Name("AVPlayerItemDidPlayToEnd")` 字面量构造 |
| tvOS app 图标 | 标准 appiconset tvOS 不认；brandassets 尺寸错的图拖垮整个 catalog 编译 | 用 brandassets 只留尺寸对的 large/small，删 ASSETCATALOG_APPICON_NAME 强制查找 |

---

## 四、最小复用清单（新项目落地）

1. **PlaybackEngine**：`urls:[URL]` + `index` + `onNeedMore`/`onRefresh` 回调 + `merge()` 追加去重 + `firstFrameReady` 标志。
2. **PlayerManager**：`players:[Int:AVPlayer]` + `prepare(center:)`(±2 窗口) + `acquire`(建 player+KVO) + `peekPlayer` + `pauseAll`。
3. **DYPlayerViewController**：UICollectionView 垂直分页 + pan 手势 + snap + `willDisplay` 绑定 + `updatePlaybackStates` + 看门狗 + 遥控 `pressesBegan`。
4. **PlayerCell**：`PlayerLayerView`(AVPlayerLayer 容器) + cover 兜底 + overlay UI，**不持 player**。
5. **SwiftUI 侧**：`NativePlayerView: UIViewControllerRepresentable` 包进 ZStack，overlay 用 zIndex 分层。

完整可运行参考：本仓库 `App/Sources/App/` 的 `PlaybackEngine.swift`、`NativePlayerView.swift`、`DYFeedClient.swift`。

---

## 五、启动加载视频过渡（可选，替代启动黑屏）

1. 加载视频打包进 bundle（如 `App/Resources/loading.mp4`），`Bundle.main.url(forResource:withExtension:)` 访问。
2. 冷启动 ZStack 顶层盖一个 `LaunchVideoOverlay`（`AVPlayerViewController` 播视频，`isMuted=true`、播完循环），遮住黑屏。
3. 主 feed 首帧 `isReadyForDisplay` → 置标志 → overlay `.transition(.opacity)` 0.6s 交叉淡化，露出底下播放器。
4. 首帧没到之前 overlay 一直循环，不会闪黑。
