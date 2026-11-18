import SwiftUI
import UIKit
import AVFoundation
import AVKit

// MARK: - 直播流屏（v193 单 AVPlayer 换 URL + AVPlayerViewController 渲染，照 myDV 全局共享 player）

/// SwiftUI 包装：直播纵向分页流（全屏）。设置面板「直播」进入；Menu 关闭回播放。
struct DYLiveFeedScreen: View {
    @ObservedObject var model = DYQuickPanelModel.shared

    var body: some View {
        DYLiveFeedView()
            .ignoresSafeArea()
            .onExitCommand { model.isLiveOpen = false }
            .transition(.opacity)
    }
}

struct DYLiveFeedView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DYLiveFeedViewController {
        DYLiveFeedViewController()
    }
    func updateUIViewController(_ uiViewController: DYLiveFeedViewController, context: Context) {}
}

/// 可聚焦 collectionView：PlayerCell `canBecomeFocused=false`（照 VOD），但直播屏需要遥控上下键锚点
/// → 让 collectionView 自己可聚焦。聚焦后遥控上下键走 live VC 的 pressesBegan 切房。
final class DYLiveFocusCollectionView: UICollectionView {
    override var canBecomeFocused: Bool { true }
}

/// 直播单房间 cell（v193）：**不渲染视频**（视频由控制器级 AVPlayerViewController 渲染，浮在 collection view 下）。
/// cell 只负责标题/观看数 overlay（透明背景，让下面的视频透出）。
/// v192 黑屏根因：把出画面的 AVPlayerViewController 换成手动 PlayerLayerView(AVPlayerLayer)——v186/v187 黑屏老路。
/// v189 出画面靠 AVPlayerViewController。正确组合 = AVPlayerViewController 管渲染 + v192 asset header。
final class LivePlayerCell: UICollectionViewCell {
    private let nicknameLabel = UILabel()
    private let descLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear   // 透明：让控制器级视频层透出
        // 左下信息区（照 VOD PC 版：@主播·X观看 / 标题）
        nicknameLabel.font = .boldSystemFont(ofSize: 32)
        nicknameLabel.textColor = .white
        nicknameLabel.shadowColor = .black
        nicknameLabel.shadowOffset = CGSize(width: 1, height: 1)
        descLabel.font = .systemFont(ofSize: 26, weight: .medium)
        descLabel.textColor = .white
        descLabel.shadowColor = .black
        descLabel.shadowOffset = CGSize(width: 1, height: 1)
        descLabel.numberOfLines = 2
        contentView.addSubview(nicknameLabel)
        contentView.addSubview(descLabel)
        isUserInteractionEnabled = false   // 照 VOD cell：排除出焦点/触摸，滑动不被干扰
    }
    required init?(coder: NSCoder) { fatalError() }
    override var canBecomeFocused: Bool { false }
    private static let textShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = UIColor.black
        s.shadowOffset = CGSize(width: 1, height: 1)
        s.shadowBlurRadius = 2
        return s
    }()
    override func layoutSubviews() {
        super.layoutSubviews()
        let b = contentView.bounds
        let infoLeft: CGFloat = 24
        let infoBottom: CGFloat = 44
        let infoW = b.width - infoLeft * 2
        descLabel.frame = CGRect(x: infoLeft, y: b.height - infoBottom - 62, width: infoW, height: 62)
        nicknameLabel.frame = CGRect(x: infoLeft, y: b.height - infoBottom - 62 - 4 - 40, width: infoW, height: 40)
    }

    /// 填标题/观看数（照 VOD applyInfo 同行排版：@主播 · X观看 / 标题）
    func configure(room: DYLiveRoom, viewerText: String) {
        let nick = room.ownerName.isEmpty ? "" : "@\(room.ownerName)"
        if nick.isEmpty && viewerText.isEmpty {
            nicknameLabel.attributedText = nil
        } else {
            let s = NSMutableAttributedString()
            if !nick.isEmpty {
                s.append(NSAttributedString(string: nick, attributes: [.font: UIFont.boldSystemFont(ofSize: 32), .foregroundColor: UIColor.white, .shadow: Self.textShadow]))
                if !viewerText.isEmpty { s.append(NSAttributedString(string: "  ·  ", attributes: [.font: UIFont.systemFont(ofSize: 26), .foregroundColor: UIColor.white.withAlphaComponent(0.7), .shadow: Self.textShadow])) }
            }
            if !viewerText.isEmpty {
                s.append(NSAttributedString(string: viewerText, attributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.white.withAlphaComponent(0.75), .shadow: Self.textShadow]))
            }
            nicknameLabel.attributedText = s
        }
        descLabel.text = room.title.isEmpty ? nil : room.title
    }
}

/// 直播纵向分页控制器（照 myDV 全局共享 player：**单 AVPlayer 换 URL**，非池）。
/// v189-v191 连败三轮根因=per-cell player 池（窗口驱逐+缓存）多 player 抢解码器 → 大部分黑屏。
/// v192 黑屏根因=手动 PlayerLayerView(AVPlayerLayer) 渲染（v186/v187 老路）。
/// v193 正确组合：**控制器级 AVPlayerViewController 渲染（v189 出画面方案）+ v192 asset header（CDN 不返回空）**。
/// 视频层浮在 collection view 下；cell 透明只显示标题/观看数 overlay；换房 replaceCurrentItem 换 URL（分页/滑动动画不动）。
final class DYLiveFeedViewController: UIViewController {
    private var collectionView: UICollectionView!
    private var currentIndex = 0
    private var didInitialScroll = false

    /// 全局共享单 player（照 myDV ij4.c 全局共享 ExoPlayer）——换房 replaceCurrentItem 换 URL，不销毁重建
    private let sharedPlayer = AVPlayer()
    /// 渲染层（v189 出画面方案：AVPlayerViewController 自己管 AVPlayerLayer）
    private let playerVC = AVPlayerViewController()
    private var hlsCache: [String: String] = [:]       // webRid → 已 resolve 的 HLS URL
    private var resolving = Set<String>()              // webRid → enter 在飞去重
    private var playingWebRid = ""                     // 当前共享 player 正在放的房间

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // 1) 视频渲染层（控制器级 AVPlayerViewController，v189 出画面方案）——加在 collection view 下面
        playerVC.showsPlaybackControls = false
        playerVC.videoGravity = .resizeAspect
        // ⚠️ v210 修 -16832 直播追边 stall（真根因，v209 渲染树+ffprobe 实锤：清单/编码/渲染全好，
        // 唯独 AVPlayer 卡在直播边缘 stall 不解首帧）。automaticallyWaitsToMinimizeStalling 默认 true
        // 会让 AVPlayer 起播前等缓冲、又追不上直播边缘 → 反复重启。关掉它=立刻起播（直播标准修法）。
        sharedPlayer.automaticallyWaitsToMinimizeStalling = false
        // ⚠️ v207 黑屏真凶修复：playerVC.player 从 v193 创建以来从未赋值！渲染层没有 player
        // → isReadyForDisplay 永远 0、全屏黑（sharedPlayer 照常出声所以"有声无画面"）。
        // 一行修复：把共享 player 接到渲染层。
        playerVC.player = sharedPlayer
        // ⚠️ tvOS 上 AVPlayerViewController.view 是 UIView?（iOS 非可选）——必须解包
        if let pv = playerVC.view {
            pv.backgroundColor = .black
            pv.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(pv)
            NSLayoutConstraint.activate([
                pv.topAnchor.constraint(equalTo: view.topAnchor),
                pv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                pv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                pv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }
        // 2) collection view（透明，标题 overlay 浮在视频上）
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collectionView = DYLiveFocusCollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.register(LivePlayerCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.panGestureRecognizer.isEnabled = false   // 关原生滚动，手势接管（照 NativePlayerView）
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        setupGestures()
        loadFeed()
    }

    private func loadFeed() {
        DYLiveClient.shared.fetchLiveFeed { [weak self] fresh in
            guard let self else { return }
            guard !fresh.isEmpty else {
                DYLog.shared.event("LIVE feed empty on open")
                return
            }
            self.collectionView.reloadData()
            self.didInitialScroll = false
            self.view.setNeedsLayout()
        }
    }

    // MARK: 手势（照 NativePlayerView：关原生滚动 + pan 阈值 100 + 焦点屏护栏）
    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard DYQuickPanelModel.shared.isOpen == false, DYSettingsModel.shared.isOpen == false,
              DYQuickPanelModel.shared.isProfileOpen == false, DYQuickPanelModel.shared.isCommentOpen == false,
              DYQuickPanelModel.shared.isMixOpen == false else { return }
        let t = g.translation(in: view)
        guard abs(t.y) > 100 else { return }
        g.setTranslation(.zero, in: view)
        if t.y < 0 { advance() } else { rewind() }
        DYLog.shared.log("LIVEFEED swipe \(t.y < 0 ? "up" : "down") -> switch")
    }

    private func advance() { scrollTo(index: centeredIndex() + 1, animated: true) }
    private func rewind() { scrollTo(index: max(0, centeredIndex() - 1), animated: true) }

    private func scrollTo(index: Int, animated: Bool) {
        let count = DYLiveClient.shared.rooms.count
        guard count > 0, index >= 0, index < count else { return }
        let clamped = min(max(0, index), count - 1)
        let pageHeight = max(1, collectionView.bounds.height)
        let maxOffset = max(0, collectionView.contentSize.height - collectionView.bounds.height)
        let targetY = min(CGFloat(clamped) * pageHeight, maxOffset)
        collectionView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
        currentIndex = clamped
        if clamped >= count - 5 { loadMoreIfNeeded() }
        DYLog.shared.log("LIVEFEED scrollTo idx=\(clamped) y=\(targetY) items=\(count)")
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.35 : 0.05)) { [weak self] in
            self?.updatePlaybackStates(center: clamped)
        }
    }

    private func centeredIndex() -> Int {
        guard collectionView.bounds.height > 0 else { return currentIndex }
        let center = CGPoint(x: collectionView.bounds.midX, y: collectionView.bounds.midY)
        if let ip = collectionView.indexPathForItem(at: center) { return ip.item }
        return Int(round(collectionView.contentOffset.y / max(1, collectionView.bounds.height)))
    }

    /// 居中房间播放（单共享 player 换 URL）
    private func updatePlaybackStates(center index: Int) {
        let rooms = DYLiveClient.shared.rooms
        guard rooms.indices.contains(index), let room = rooms[index] as DYLiveRoom? else { return }
        playRoom(room)
    }

    /// 播房间：resolve HLS（缓存优先）→ 共享 player 换 URL（AVPlayerViewController 渲染）→ play
    private func playRoom(_ room: DYLiveRoom) {
        if playingWebRid == room.webRid { return }   // 已在放同一房间
        if let hls = hlsCache[room.webRid] {
            play(url: hls, webRid: room.webRid)
            return
        }
        let feedHls = DYLiveClient.bestHlsUrl(room.hlsUrls)
        if !feedHls.isEmpty {
            hlsCache[room.webRid] = feedHls
            play(url: feedHls, webRid: room.webRid)
            return
        }
        guard !resolving.contains(room.webRid) else { return }
        resolving.insert(room.webRid)
        DYLog.shared.log("LIVEFEED resolve webRid=\(room.webRid)")
        DYLiveClient.shared.enterRoom(room.webRid) { [weak self] entered in
            guard let self else { return }
            self.resolving.remove(room.webRid)
            guard let entered else {
                DYLog.shared.event("LIVEFEED resolve fail webRid=\(room.webRid)")
                return
            }
            let hls = DYLiveClient.bestHlsUrl(entered.hlsUrls)
            guard !hls.isEmpty else {
                DYLog.shared.event("LIVEFEED resolve no-hls webRid=\(room.webRid)")
                return
            }
            self.hlsCache[room.webRid] = hls
            self.play(url: hls, webRid: room.webRid)
        }
    }

    /// 共享 player 换 URL（先剥嵌套清单 → 裸 AVURLAsset（myDV live 无任何头）→ AVPlayerViewController 渲染）
    private func play(url: String, webRid: String) {
        guard playingWebRid != webRid, let u = URL(string: url) else { return }
        // v208：先剥嵌套清单——L1 媒体清单的"片段"可能指向 L2 m3u8（非标准 HLS 链式结构，
        // hls.js 会递归解析但 AVPlayer 对这种结构行为不可控）。L2 才是真 TS 片段清单。
        resolvePlaylist(url) { [weak self] finalUrl in
            guard let self else { return }
            // v208：裸 AVURLAsset——myDV live 路径 OkHttpDataSource 无任何自定义头（agent 实锤
            // fo5 头表仅 VOD 用，live 走裸 client），实测带头/无头清单一致 → 完全对齐原项目
            let asset = AVURLAsset(url: URL(string: finalUrl)!)
            let item = AVPlayerItem(asset: asset)
            // v210：item 级缓冲余量（避免 seek 到边缘后方后又立刻追边 stall）。preferredForwardBufferDuration 是 AVPlayerItem 属性。
            item.preferredForwardBufferDuration = 4.0
            self.sharedPlayer.replaceCurrentItem(with: item)
            self.playingWebRid = webRid
            self.sharedPlayer.play()
            DYLog.shared.event("LIVEFEED play webRid=\(webRid) final=\(finalUrl.prefix(70))")
            // v210 修 -16832 直播追边 stall（真根因）。v209 的 status-KVO seek-back 一次没触发——
            // 因为 .readyToPlay 那一刻 seekableTimeRanges 还没填充（count=0 实锤）。改用轮询：
            // 起播后每隔 0.5s 查 seekableTimeRanges，一旦有值就 seek 到「边缘后方 ~2 段」的稳定点，
            // 避开正在写的最后一段（清单 target=5s → 退 10s），让 AVPlayer 有缓冲可解首帧。
            pollAndSeekBehindLiveEdge(webRid: webRid, attempts: 0)
            // v204/v209 设备端诊断：errorLog/accessLog/presentationSize/isReadyForDisplay + 渲染树
            for delay in [3.0, 8.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.playingWebRid == webRid, let item = self.sharedPlayer.currentItem else { return }
                    // v209 修 rfd 假阴性：playerVC.view 根 layer 不是 AVPlayerLayer（是普通容器），
                    // 旧代码 `view?.layer as? AVPlayerLayer` 永远 cast 失败 → rfd 恒 0（49 次全 0）。
                    // 改：递归在 sublayer 树里找真正的 AVPlayerLayer。
                    let rootLayer = self.playerVC.view?.layer
                    let layer = rootLayer.flatMap(findPlayerLayer)
                    let rfd = layer?.isReadyForDisplay ?? false
                    let ps = item.presentationSize
                    DYLog.shared.log("LIVE DIAG t=\(delay) status=\(item.status.rawValue) tc=\(self.sharedPlayer.timeControlStatus.rawValue) t=\(String(format: "%.1f", self.sharedPlayer.currentTime().seconds)) ps=\(Int(ps.width))x\(Int(ps.height)) rfd=\(rfd ? 1 : 0) itemErr=\(item.error?.localizedDescription ?? "-")")
                    // v209：dump 渲染层树 + frame，判定 AVPVC.view 到底有没有尺寸/有没有接上 playerLayer
                    if let rl = rootLayer {
                        DYLog.shared.log("LIVE RENDER root frame=\(self.playerVC.view?.frame ?? .zero) sublayers=\(rl.sublayers?.count ?? 0)")
                        dumpRenderTree(rl, depth: 1)
                    } else {
                        DYLog.shared.log("LIVE RENDER root layer nil (playerVC.view 未就绪?)")
                    }
                    if let errLog = item.errorLog(), !errLog.events.isEmpty {
                        for (i, e) in errLog.events.prefix(3).enumerated() {
                            let uri = (e.uri as String?) ?? "-"
                            DYLog.shared.log("LIVE DIAG err[\(i)] code=\(e.errorStatusCode) domain=\(e.errorDomain) uri=\(uri.prefix(70)) comment=\((e.errorComment as String?) ?? "-")")
                        }
                    } else {
                        DYLog.shared.log("LIVE DIAG errLog empty")
                    }
                    if let accLog = item.accessLog(), !accLog.events.isEmpty {
                        for (i, e) in accLog.events.suffix(3).enumerated() {
                            let uri = (e.uri as String?) ?? "-"
                            DYLog.shared.log("LIVE DIAG acc[\(i)] bytes=\(e.numberOfBytesTransferred) uri=\(uri.prefix(70))")
                        }
                    } else {
                        DYLog.shared.log("LIVE DIAG accLog empty")
                    }
                }
            }
        }
    }

    /// v210：轮询等 seekableTimeRanges 填充，然后 seek 到直播边缘后方 ~2 段的稳定点（修 -16832 追边 stall）。
    /// .readyToPlay 那刻 ranges 通常还是空，所以不能用 status-KVO——必须轮询。
    private func pollAndSeekBehindLiveEdge(webRid: String, attempts: Int) {
        guard attempts < 20 else {
            DYLog.shared.log("LIVEFEED seek-poll give up (20 次无 seekableTimeRanges)")
            return
        }
        guard playingWebRid == webRid, let item = sharedPlayer.currentItem else { return }
        if let range = item.seekableTimeRanges.last?.timeRangeValue,
           CMTimeGetSeconds(range.duration) > 0 {
            let start = CMTimeGetSeconds(range.start)
            let edge = start + CMTimeGetSeconds(range.duration)
            let target = max(start, edge - 10.0)   // 退 2 段（target duration 5s）
            if target.isFinite, target > 0 {
                DYLog.shared.log("LIVEFEED seek-behind edge=\(String(format: "%.2f", edge)) -> \(String(format: "%.2f", target)) (修 -16832, attempts=\(attempts))")
                sharedPlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600))
                return
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.pollAndSeekBehindLiveEdge(webRid: webRid, attempts: attempts + 1)
        }
    }

    /// v209：递归在 layer 树里找真正的 AVPlayerLayer（playerVC.view 根 layer 是普通容器，
    /// 直接 `as? AVPlayerLayer` 永远失败 → 旧 rfd 恒 0 假阴性）。
    private func findPlayerLayer(_ layer: CALayer) -> AVPlayerLayer? {
        if let p = layer as? AVPlayerLayer { return p }
        for sub in layer.sublayers ?? [] {
            if let found = findPlayerLayer(sub) { return found }
        }
        return nil
    }

    /// v209：dump 渲染层树（class + frame），真机判定 AVPVC.view 有没有尺寸、AVPlayerLayer 有没有挂上。
    private func dumpRenderTree(_ layer: CALayer, depth: Int) {
        guard depth <= 4 else { return }
        let indent = String(repeating: "  ", count: depth)
        let cls = String(describing: type(of: layer))
        let f = layer.frame
        DYLog.shared.log("LIVE RENDER \(indent)- \(cls) frame=(\(Int(f.origin.x)),\(Int(f.origin.y)),\(Int(f.width)),\(Int(f.height)))")
        for sub in layer.sublayers ?? [] {
            dumpRenderTree(sub, depth: depth + 1)
        }
    }

    /// v208：剥嵌套清单——L1 媒体清单的"片段行"若是 m3u8（非标准链式结构），改播 L2 URL。
    /// 平铺 TS 清单（片段行=.ts）原样返回。
    private func resolvePlaylist(_ url: String, done: @escaping (String) -> Void) {
        guard let u = URL(string: url) else { done(url); return }
        URLSession.shared.dataTask(with: u) { data, _, _ in
            guard let data, let text = String(data: data, encoding: .utf8), text.contains("#EXTM3U") else {
                DispatchQueue.main.async { done(url) }
                return
            }
            let seg = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && !$0.hasPrefix("#") } ?? ""
            if seg.contains(".m3u8") {
                let abs = seg.hasPrefix("http") ? seg : (URL(string: seg, relativeTo: u)?.absoluteString ?? seg)
                DYLog.shared.log("LIVEFEED nested unwrap L1→L2 \(abs.prefix(80))")
                DispatchQueue.main.async { done(abs) }
            } else {
                DispatchQueue.main.async { done(url) }
            }
        }.resume()
    }

    /// 直播流 header（照 VOD playbackHeaders web 分支：Referer+UA+ttwid；绝不加 sec-ch-ua，v157 铁律）
    private func liveHeaders() -> [String: String] {
        var h: [String: String] = [:]
        h["User-Agent"] = DYLiveClient.liveUA
        h["Referer"] = "https://live.douyin.com/"
        let ttwid = DYDanmakuClient.shared.ttwidValue
        if !ttwid.isEmpty { h["Cookie"] = "ttwid=\(ttwid)" }
        return h
    }

    private func loadMoreIfNeeded() {
        guard !DYLiveClient.shared.isLoadingMore else { return }
        DYLiveClient.shared.loadMore { [weak self] fresh in
            guard let self, !fresh.isEmpty else { return }
            self.collectionView.reloadData()
        }
    }

    // MARK: 遥控（照 NativePlayerView pressesBegan：上下切房，Menu 关闭走 SwiftUI onExitCommand）
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if DYQuickPanelModel.shared.isProfileOpen || DYQuickPanelModel.shared.isCommentOpen
                || DYQuickPanelModel.shared.isMixOpen {
            super.pressesBegan(presses, with: event)
            return
        }
        for press in presses {
            switch press.type {
            case .downArrow: advance(); return
            case .upArrow: rewind(); return
            default: break
            }
        }
        super.pressesBegan(presses, with: event)
    }
}

extension DYLiveFeedViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        DYLiveClient.shared.rooms.count
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! LivePlayerCell
        let idx = indexPath.item
        let rooms = DYLiveClient.shared.rooms
        if rooms.indices.contains(idx) {
            let room = rooms[idx]
            let viewerText = room.userCount.isEmpty ? "" : "\(room.userCount)观看"
            cell.configure(room: room, viewerText: viewerText)
        }
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        collectionView.bounds.size
    }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, withTargetContentOffset targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let pageHeight = max(1, scrollView.bounds.height)
        let targetY = targetContentOffset.pointee.y
        let snappedY = (velocity.y >= 0 ? ceil(targetY / pageHeight) : floor(targetY / pageHeight)) * pageHeight
        targetContentOffset.pointee.y = snappedY
    }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updatePlaybackStates(center: centeredIndex())
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updatePlaybackStates(center: centeredIndex())
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didInitialScroll, !DYLiveClient.shared.rooms.isEmpty, collectionView.bounds.height > 0 {
            didInitialScroll = true
            let idx = min(currentIndex, DYLiveClient.shared.rooms.count - 1)
            currentIndex = idx
            scrollTo(index: idx, animated: false)
        }
    }
}
