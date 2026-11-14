# DYTV 交接文档（v147 · 2026-11-15 全面重构版）

> **维护规则（v148 起）**：新内容只更新对应章节（§5 未解决/§6 踩坑/§8 方向/§7 字段表），不再按版本堆叠新章节；版本细节以 git log + 记忆文件为准。

> 本文档取代此前所有过时交接。所有结论均基于工具读取的实际代码与日志，非记忆。
> **当前版本 v150**。稳定回退点：**v122**（git checkout 三文件）。
> 最新验收状态：播放线全收工（v128-v131 用户"趋近完美"）；双源架构全通（v135）；弹幕=⏸️暂停待重启（v142 反馈未达点子）；PC 版 UI v143-v145 已按反馈修正待验收；评论已实装、作者主页被 UIFID 风控墙挡住（v147）。

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
- **快捷悬浮窗**（DYQuickPanel）：确认键短按呼出，**屏幕底部居中横向卡片**（v149 修复：RootView ZStack 是 alignment:.leading，外层 VStack 必须 frame(maxWidth:.infinity) 才不被钉在左侧）；标准液态玻璃无 tint 透出视频；主页/评论/合集(条件)/不感兴趣。**两倍速=触摸板悬停 1s**（手指放触摸区不动，与滑动同区域；v149 定版，v146 长按 1.5s/v148 确认键长按都是弯路）。
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
| v150 | 弹幕 canShoot 门控+轨道卡死 10s 自愈+DMSYNC 诊断；行距加大（轨道高 50）；悬停倍速 0.6s/漂移容限 140/必留日志+▶▶2x 角标；主页合集 toast 反馈（探针实锤作品列表需登录态） | ✅ CI 过，待验收 |

## 5. 未解决问题清单（按优先级）

### 5.1 新视频卡顿（播放体验，用户未拍板方案）
- **现象**：刷到新视频后过几秒才触发播放（forward ready 0-3s，用户刷速快于预载；回看旧视频走 redirect 0-16s）。
- **已分析根因**：①每视频不同 CDN 域名 → 每次 acquire 新 DNS+TLS；②驱逐半径 ±2 窄，回看必重取；③v136 idle=2s 有误杀风险（本会话未触发但存在）；④redirect 302 出的 CDN 不可控（16s 尾部）。
- **候选方案（待拍板）**：A 驱逐半径对称 ±3（解码器 ≤7 仍限内）；B idle 2s→4s 回退；C redirect>5s fallback static 重试；D 预取窗口 [idx-1, idx+3] 前向偏移。建议组合 A+B+D。

### 5.2 弹幕间歇空窗（v150 双候选根因同治 + 诊断就位，待验收）
- **现象（用户澄清）**：明显的「获取→展示」循环——一段时间一条都没有，过一会儿扎堆出现，~40s 周期循环。
- **已排除**：数据空窗（直方图探针：1212 条连续无零桶）；数据不全（自适应切分已取全量）；**v149 真机日志：数据侧全净**（1172 条 7s 取完/0 重试/0 失败段）——空窗铁定在发射/轨道层。
- **v150 两个候选根因同治**：①发射器 canShoot 门控（此前被轨道拒的弹幕被 shotIds 永久标记=白白损失，密集段过后无弹可射）；②DanmakuKit 轨道释放疑点（track.pause 的 removeAllAnimations 触发 animationDidStop(flag=false) 不释放 cell；animationDidStop(flag=true) 是唯一释放路径，真机是否触发未证）→ DMJANITOR 兜底（due>0 且 10s 零发射=轨道卡死 → clean() 强制清轨）。
- **裁决机制（下轮日志）**：DMSYNC 每 4s 一条（t/due/marked/items/stall）——若空窗期 due>0 且 DMJANITOR 频繁触发=轨道释放真凶（下一步换成主动巡检 realFrame 释放或换渲染方案）；若空窗期 due=0=数据/offset_time 问题（换 offset_time 语义探针）。
- **已做保留**：数据链全通；样式=纯白字无底无描边；顶部 6 行/不重叠/280px/s；dm_drop/dm_shoot/dm_items/dm_janitor 计数器。
- **重启入口**：DYDanmakuOverlay.tick + 探针 `_tmp/danmaku_hist_probe.js` / `danmaku_segment_probe.js`。

### 5.3 作者主页作品列表（两道墙已探明，需登录态解锁）
- **web 墙**：`/aweme/v1/web/aweme/post/` → 403 `ArgusSecurityPlugin Uifid Not Found`（myDV 同 blocked）。UIFID 链已挖到 uz0 协程 POST 申请（X-Secsdk-Csrf-Token: DOWNGRADE），调用方 URL 未挖到。
- **mobile 墙（v150 探针实锤，`_tmp/mobile_post_probe.js`）**：`aweme.snssdk.com/aweme/v1|v2/aweme/post/` **无风控墙**（http=200 status_code=0，a_bogus 签名即过），但匿名设备一律返回**空 aweme_list**（sec_user_id 与 user_id/max_time 两种参数形态、3 个作者全试过）——作品列表被登录态卡死，不是签名问题。
- **解锁路径**：扫码登录（路线 v2-v8 已验证，铁律允许仅登录用 WebView）→ 拿到 cookie 后 mobile post 端点大概率直接可用（比挖 UIFID 链靠谱）。
- **v150 占位反馈**：主页/合集点击给 toast「需登录支持，即将上线」（不再点了没反应）。
- **已有资产**：sec_uid=author f191（实测）；works API 参数表全录（web+mobile 双形态）；zq5 有 UserWorksResponse 解析参照。

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
5. desc=f2（含内联话题）、纯话题行=f459、省=f279、author f4（f3=昵称、f191=sec_uid、f2=uid 数字）、statistics=f10（f3赞 f2评 f6享 f11藏 f5播）、mix 候选=f14（内含合集名 f5）——**全部 wire 实测**。
6. `authentication_token` mobile proto 无此字段且**传空能通**（弹幕/评论均验证）。

### 6.5 架构/流程坑
1. 同一路线连败 3+ 版 → 果断回退稳定底座，别让用户连续当测试员。
2. 改代码前必读实际文件+反编译（凭记忆=幻觉）。
3. `exit(0)` sideload 可用（设置面板 menu#2 退出）。
4. tvOS 焦点链：面板/列表打开时按键走 SwiftUI（onExitCommand/按钮），VC.pressesBegan 收不到——两套面板的按键处理必须各自实现，且互不干扰（焦点链隔离是特性不是 bug）。
5. 大响应/多连接的日志重复问题——分析前按行去重。
6. **串行队列内联回调 + 同队列 queue.sync = 自等待死锁（v147/v148 评论「闪退」真根因，v148 焦点理论被真机证伪）**：ttwid 已缓存时 ensureTTWID 的 done() 在 danmaku 队列内联执行，DYCommentClient.fetchPages 在同队列调 ttwidValue（queue.sync）→ 队列永久卡死 → 主线程的 ttwidValue（DYFeedClient 翻页/PlayerManager 播放头）跟着卡死 → 应用冻结被杀。日志特征：CMT 请求一行都没出现 + 操作后不久 ROOT auto-start。修复=跨模块回调永远先 DispatchQueue.main.async 跳出工作队列。焦点兜底（可聚焦元素/Button）仍是有益实践，但不是本例根因。
7. 两倍速触发方式用户三次改口径后定版：**触摸板悬停不动**（与滑动同区域），v146 触摸板长按 1.5s / v148 确认键长按 0.6s 都是弯路；最终=UILongPressGestureRecognizer minimumPressDuration 1.0 + allowableMovement 60。

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

### 7.2 web 端点（JSON，全部已验证/可验证）
| 端点 | 关键参数 | 状态 |
|---|---|---|
| `/aweme/v1/web/tab/feed/` | b0 配方（aweme_pc_rec_raw_data/filterGids/refresh_index/pull_type/video_type_select...）+ webCommon | ✅ 双源已用 |
| `/aweme/v1/web/danmaku/get_v2/` | u11.K 参数 + webCommon；**60s 分段**（单响应 ~460 上限）；offset_time/text | ✅ 已用 |
| `/aweme/v1/web/comment/list/` | aweme_id/cursor/count=20；{comments[{cid,user.nickname,avatar_thumb,text,digg_count,create_time}],has_more,cursor} | ✅ v147 已用 |
| `/aweme/v1/web/aweme/post/` | sec_user_id/max_cursor/need_time_list 等（u11:3683 原样） | ❌ 403 UIFID 墙（待 uz0 链） |
| `/aweme/v1/web/mix/listcollection/` | cursor/count | ❌ 同 UIFID 墙（myDV 也 blocked） |
| ttwid 注册 | POST ttwid.bytedance.com/ttwid/union/register/（body/headers u11.A 原文） | ✅ 匿名可用 |
| webCommon（必需） | device_platform=webapp&aid=6383&channel=channel_pc_web&cookie_enabled=true&browser_* | 缺则 "AppId不合法" |
| 签名 | getABogus(query,data,path,webUA) + timestamp 参数；a_bogus 后置 | ✅ 评论/弹幕/tab feed 全验证 |

## 8. 未来开发方向（路线图）

### 8.1 短期（体验收尾）
1. **新视频卡顿**：按 §5.1 组合 A+B+D 实施（等用户拍板）。
2. **弹幕重启**：按 §5.2 疑点顺序排查（offset_time 语义 → 轨道时序 → 时序对齐），数据说话。
3. **评论滚动加载更多**：cursor 分页已支持，触底加载 + "加载更多"按钮。
4. **悬浮窗补暂停/播放项**（OK 键被占用后暂停功能缺口）。

### 8.2 中期（功能扩展）
1. **作者主页**：挖通 UIFID 申请链（uz0 调用方）→ works API → 作品列表屏（封面网格+点击播放，复用 merge 管道）。
2. **合集浏览**：mix/listcollection（同 UIFID 墙，一起解决）。
3. **搜索**：顶部搜索条 UI + web 搜索端点（myDV 有 search/single 端点参照）。
4. **扫码登录**：解锁登录态（更全数据/收藏/关注流）；网页套壳路线 v2-v8 已验证可行（铁律允许仅登录用 WebView）。
5. **直播**：myDV LiveWebSocket（kq2.java）参照。

### 8.3 长期（打磨）
1. UI 美化统一轮：启动 spinner（v76 曾有）、弹幕样式设置、主题。
2. 弹幕设置项扩展（密度/字号/速度/透明度）。
3. 设置面板持久化扩展（各项 UserDefaults）。
4. App 图标（actool Assets.car 问题未解，已搁置）。

## 9. 关键文件
- `NativePlayerView.swift`：播放层全部（池/看门狗/手势/进度条/PC UI/PlayerCell）。
- `DYFeedClient.swift`：双源数据 + 解析（Proto 解码/选链/过滤/信息提取）。
- `PlaybackEngine.swift`：引擎状态（urls/infos/durations/rawVideos/redirectUrls + reset/merge）。
- `DYDanmakuClient.swift` / `DYDanmakuOverlay.swift`：弹幕（⏸️暂停）。
- `DYCommentClient.swift`：评论数据。
- `DYQuickPanel.swift`：快捷悬浮窗 + 评论屏（SwiftUI）。
- `DYSettingsModel.swift`：设置面板 + 快捷面板模型（SwiftUI）。
- `DYSigner.swift`：4 参 a_bogus 签名（JavaScriptCore + Signer JS 资产）。
- `DYLog.swift`：日志 + LAN 服务器（/log /stat /ping /clear）+ count()/event()。
- `HANDOVER.md`（本文档）、`MYDV_FEED_BLUEPRINT.md`（数据蓝图）、记忆文件 `dytv-*-*.md`。
- 探针：`_tmp/danmaku_probe.js`、`webfeed_probe.js`、`danmaku_hist_probe.js`、`comment_works_probe.js`、`aweme_fields_probe.js`。
- 反编译：`_apk_work/jadx_out_classes/sources/defpackage/u11.java`（API 总集）+ `com/github/mytv/dv/model/`（JSON 模型）+ `s13`（jadx_out，protobuf 解析权威）。

## 10. 给下一个 AI 的明确指令
1. **先读本文档 §7 权威表 + 实际代码 + 反编译**，禁止凭记忆/猜测。
2. **数据获取类改动：先开发机 Node 探针验证**（`_tmp/*probe.js` 复用），数据说话再进真机。
3. **治播放/数据 bug 先问 myDV 原项目**（u11.java = DouyinDirectApi 全集；缺失类如 s13/dp5 记录在案，改用 wire 实测）。
4. **同一路线连败 3+ 版 → 回退稳定底座**（当前 v122/v147），别让用户连续当测试员。
5. **大段重写后必须 diff 检查历史修复点**（v143/v144 两次返工教训）。
6. **CI/日志/编译的坑先查 §6**，已知问题别再踩一遍。
7. 每版交付后更新本文档 + 记忆文件；版本号 +1 禁止重复。
