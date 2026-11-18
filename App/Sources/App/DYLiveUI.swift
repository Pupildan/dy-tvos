import SwiftUI
import UIKit
import AVFoundation
import AVKit
import KSPlayer

// MARK: - 直播流屏（v212 播放内核 AVPlayer→KSPlayer/KSMEPlayer。铁律：只有直播内核能换，VOD/主feed/loading 不动）
// v185→v211 十几轮实锤：AVPlayer 对抖音直播 HLS 卡 -16832 追边 stall 永远解不出首帧（ffprobe 证实流/渲染层都好）。
// 换 KSMEPlayer（FFmpeg 软解，独立 HLS demuxer）绕开 AVPlayer 整套 live-edge 逻辑。

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

/// 直播纵向分页控制器（v212 播放内核 AVPlayer→KSPlayer/KSMEPlayer，照 myDV 全局共享单 player 换 URL，非池）。
/// v189-v191 连败三轮根因=per-cell player 池（窗口驱逐+缓存）多 player 抢解码器 → 大部分黑屏。
/// v185→v211 AVPlayer 路径：渲染层/流/编码全好（ffprobe+渲染树实锤），唯独 AVPlayer 卡 -16832 追边 stall 解不出首帧。
/// v212 换 KSMEPlayer（FFmpeg 软解，独立 HLS demuxer）绕开 AVPlayer 整套 live-edge 逻辑。
/// 视频层浮在 collection view 下；cell 透明只显示标题/观看数 overlay；换房 makeView(新URL) 换流（分页/滑动动画不动）。
final class DYLiveFeedViewController: UIViewController {
    private var collectionView: UICollectionView!
    private var currentIndex = 0
    private var didInitialScroll = false

    /// KSPlayer 协调器（持 KSPlayerLayer，换房 makeView(新URL) 内部走 playerLayer.set(url:) 换流）
    /// ⚠️ Coordinator 是 @MainActor——在 viewDidLoad（主线程）里初始化，避免属性初始化器的 actor 隔离问题。
    private var ksCoordinator: KSVideoPlayer.Coordinator!
    /// 视频渲染容器（KSPlayer 的 player.view 加在这里面，浮在 collection view 下）
    private let ksContainer = UIView()
    private var ksViewAdded = false
    private var hlsCache: [String: String] = [:]       // webRid → 已 resolve 的 HLS URL
    private var resolving = Set<String>()              // webRid → enter 在飞去重
    private var playingWebRid = ""                     // 当前共享 player 正在放的房间
    private var lastKSPlayLogAt = TimeInterval(0)      // v212 onPlay 节流（0.1s 定时器驱动，不节流会刷爆日志）

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // 1) 视频渲染层（v212 KSPlayer/KSMEPlayer）——先锁 FFmpeg 软解，再建容器（视频 view 在 play() 里 makeView 后加进来）
        // ⚠️ 锁 KSMEPlayer 是换内核的真正价值：AVPlayer 卡 -16832 追边 stall，FFmpeg 有独立 HLS demuxer 绕开它。
        //    若落回 KSAVPlayer（KSPlayer 对 AVPlayer 的封装）= 换汤不换药还是同一个 stall。
        KSOptions.firstPlayerType = KSMEPlayer.self
        ksCoordinator = KSVideoPlayer.Coordinator()
        setupKSCallbacks()
        ksContainer.backgroundColor = .black
        ksContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ksContainer)
        NSLayoutConstraint.activate([
            ksContainer.topAnchor.constraint(equalTo: view.topAnchor),
            ksContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ksContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ksContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
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

    /// KSPlayer 换流播房（v212）。makeView 幂等：同 URL 返回已有 view，URL 变了内部走 playerLayer.set(url:) 换流。
    /// 不再剥嵌套清单——KSMEPlayer 用 FFmpeg 自己的 HLS demuxer，不吃 AVPlayer 那套嵌套限制。
    private func play(url: String, webRid: String) {
        guard playingWebRid != webRid, let u = URL(string: url) else { return }
        playingWebRid = webRid
        DYLog.shared.event("LIVEFEED play(KS) webRid=\(webRid) url=\(url.prefix(70))")
        // makeView 返回 KSPlayerLayer 的 player.view；首次加进 ksContainer 并锚满四边，之后复用同一 view
        let v = ksCoordinator.makeView(url: u, options: makeKSOptions())
        if !ksViewAdded {
            v.backgroundColor = .black
            v.translatesAutoresizingMaskIntoConstraints = false
            ksContainer.addSubview(v)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: ksContainer.topAnchor),
                v.bottomAnchor.constraint(equalTo: ksContainer.bottomAnchor),
                v.leadingAnchor.constraint(equalTo: ksContainer.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: ksContainer.trailingAnchor),
            ])
            ksViewAdded = true
        }
    }

    /// v212：KSPlayer 状态回调（替代原 AVPlayer 的 LIVE DIAG）。
    /// KSPlayer 无 isReadyForDisplay/首帧回调——`.bufferFinished` 是"画面正在渲染"的代理信号。
    private func setupKSCallbacks() {
        ksCoordinator.onStateChanged = { [weak self] _, state in
            DYLog.shared.log("LIVE KS state=\(state.description) webRid=\(self?.playingWebRid ?? "-")")
        }
        ksCoordinator.onPlay = { [weak self] current, total in
            // onPlay 由 KSPlayerLayer 0.1s 定时器驱动（每秒 ~10 次）——节流到每 5s 记一条，否则刷爆日志。
            guard let self else { return }
            let now = Date().timeIntervalSince1970
            guard now - self.lastKSPlayLogAt >= 5.0 else { return }
            self.lastKSPlayLogAt = now
            DYLog.shared.log("LIVE KS onPlay cur=\(String(format: "%.1f", current)) total=\(String(format: "%.1f", total)) webRid=\(self.playingWebRid)")
        }
        ksCoordinator.onFinish = { [weak self] _, error in
            DYLog.shared.log("LIVE KS finish err=\(error?.localizedDescription ?? "-") webRid=\(self?.playingWebRid ?? "-")")
        }
    }

    /// v212：直播 KSOptions（KSMEPlayer 走 FFmpeg，认证用 formatContextOptions，直播零自定义头 v208 实锤）。
    private func makeKSOptions() -> KSOptions {
        let o = KSOptions()
        o.isLoopPlay = true   // 直播流断了自动重连
        // 缓冲 preferredForwardBufferDuration 保持默认 3.0——v210 教训：直播缓冲参数乱动会回归，先不碰。
        return o
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
