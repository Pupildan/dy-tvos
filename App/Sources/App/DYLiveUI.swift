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

    /// 共享 player 换 URL（AVPlayerViewController 渲染 + AVURLAsset 带 header）
    private func play(url: String, webRid: String) {
        guard playingWebRid != webRid, let u = URL(string: url) else { return }
        // 照 VOD NativePlayerView.swift:423：AVURLAsset 带 header（裸 AVPlayerItem 没带 → CDN 返回空 → 黑屏）
        let asset = AVURLAsset(url: u, options: ["AVURLAssetHTTPHeaderFieldsKey": liveHeaders()])
        let item = AVPlayerItem(asset: asset)
        sharedPlayer.replaceCurrentItem(with: item)
        playingWebRid = webRid
        sharedPlayer.play()
        DYLog.shared.event("LIVEFEED play webRid=\(webRid) hls=\(url.prefix(70))")
        // v204 设备端终极诊断：AVPlayerItem 自带 errorLog/accessLog + presentationSize + isReadyForDisplay
        // （探针实锤全是 H.264+AAC 且嵌套清单——编码假设已排除，要看 AVPlayer 自己怎么抱怨）
        for delay in [3.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.playingWebRid == webRid, let item = self.sharedPlayer.currentItem else { return }
                let layer = (self.playerVC.view?.layer as? AVPlayerLayer)
                let rfd = layer?.isReadyForDisplay ?? false
                let ps = item.presentationSize
                DYLog.shared.log("LIVE DIAG t=\(delay) status=\(item.status.rawValue) tc=\(self.sharedPlayer.timeControlStatus.rawValue) t=\(String(format: "%.1f", self.sharedPlayer.currentTime().seconds)) ps=\(Int(ps.width))x\(Int(ps.height)) rfd=\(rfd ? 1 : 0) itemErr=\(item.error?.localizedDescription ?? "-")")
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
                        DYLog.shared.log("LIVE DIAG acc[\(i)] bytes=\(e.numberOfBytesTransferred) segs=\(e.numberOfServerAddressChanges) uri=\(uri.prefix(70))")
                    }
                } else {
                    DYLog.shared.log("LIVE DIAG accLog empty")
                }
                item.asset.loadTracks(withMediaType: .video) { tracks, _ in
                    DYLog.shared.log("LIVE DIAG videoTracks=\(tracks?.count ?? -1)")
                    if let f = tracks?.first?.formatDescriptions.first {
                        let d = CMVideoFormatDescriptionGetDimensions(f as! CMVideoFormatDescription)
                        DYLog.shared.log("LIVE DIAG videoDims=\(d.width)x\(d.height)")
                    }
                }
                item.asset.loadTracks(withMediaType: .audio) { tracks, _ in
                    DYLog.shared.log("LIVE DIAG audioTracks=\(tracks?.count ?? -1)")
                }
            }
        }
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
