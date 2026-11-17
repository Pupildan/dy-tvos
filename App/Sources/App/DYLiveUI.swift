import SwiftUI
import UIKit
import AVFoundation
import AVKit

// MARK: - 直播流屏（v192 单 AVPlayer 换 URL，照 myDV 全局共享 player + VOD asset header）

/// SwiftUI 包装：直播纵向分页流（全屏）。设置面板「直播」进入；Menu 关闭回播放。
/// v186：删掉右上角返回按钮——它抢焦点导致遥控上下键被 SwiftUI 焦点引擎吃掉、切不了房。
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

/// 直播单房间 cell（v192 简化）：不再各自持 player，只渲染 + 标题/观看数 overlay。
/// 出画面的 AVPlayer 在控制器级（单实例换 URL，照 myDV 全局共享 player）；cell 只 bind 共享 player 渲染。
/// 照 VOD PlayerCell 结构（playerLayerView + cover + PC 版 overlay）——VOD 这套真机出画面，照抄。
final class LivePlayerCell: UICollectionViewCell {
    let playerLayerView = PlayerLayerView()
    let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.backgroundColor = .black
        iv.isHidden = true
        return iv
    }()
    private let nicknameLabel = UILabel()
    private let descLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        contentView.addSubview(playerLayerView)
        contentView.addSubview(coverImageView)
        playerLayerView.playerLayer.videoGravity = .resizeAspect
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
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayerView.frame = contentView.bounds
        coverImageView.frame = contentView.bounds
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
    /// bind 共享 player 渲染（出画面 = AVPlayerLayer + VOD asset header）
    func bind(player: AVPlayer) {
        playerLayerView.player = player
    }
    func unbind() {
        playerLayerView.player = nil
    }
    func setCover(_ image: UIImage?) {
        coverImageView.image = image
    }
    func setCoverVisible(_ visible: Bool) {
        coverImageView.isHidden = !visible
    }
    private static let textShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = UIColor.black
        s.shadowOffset = CGSize(width: 1, height: 1)
        s.shadowBlurRadius = 2
        return s
    }()
}

/// 直播纵向分页控制器（照 myDV 全局共享 player：**单 AVPlayer 换 URL**，非池）。
/// v189-v191 连败三轮的根因=per-cell player 池（窗口驱逐+缓存）多 player 抢解码器 → 大部分黑屏。
/// myDV 反编译实锤：整个滑动会话只有一个 ExoPlayer，换房 setMediaItem(newUrl).prepare() 换 URL，无池。
/// 且 VOD 出画面用 AVURLAsset 带 AVURLAssetHTTPHeaderFieldsKey（Referer+UA），我直播之前用裸 AVPlayerItem 没带 → CDN 返回空。
final class DYLiveFeedViewController: UIViewController {
    private var collectionView: UICollectionView!
    private var currentIndex = 0
    private var didInitialScroll = false

    /// 全局共享单 player（照 myDV ij4.c 全局共享 ExoPlayer）——换房 replaceCurrentItem 换 URL，不销毁重建
    private let sharedPlayer = AVPlayer()
    private var hlsCache: [String: String] = [:]       // webRid → 已 resolve 的 HLS URL
    private var resolving = Set<String>()              // webRid → enter 在飞去重
    private var playingWebRid = ""                     // 当前共享 player 正在放的房间

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collectionView = DYLiveFocusCollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.register(LivePlayerCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .black
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
        // setContentOffset 替代 scrollToItem（后者 flow layout 未就绪抛 NSException，.ips 实锤）
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

    /// 居中房间播放，非居中 pause（单共享 player；只有居中 cell bind 出画面）
    private func updatePlaybackStates(center index: Int) {
        let rooms = DYLiveClient.shared.rooms
        guard rooms.indices.contains(index) else { return }
        let room = rooms[index]
        for cell in collectionView.visibleCells {
            guard let c = cell as? LivePlayerCell,
                  let ip = collectionView.indexPath(for: c) else { continue }
            let isCenter = (ip.item == index)
            if isCenter {
                c.bind(player: sharedPlayer)
            } else {
                c.unbind()
            }
        }
        playRoom(room)
    }

    /// 播房间：resolve HLS（缓存优先）→ AVURLAsset 带 header（黑屏关键）→ 共享 player 换 URL → play
    private func playRoom(_ room: DYLiveRoom) {
        if playingWebRid == room.webRid { return }   // 已在放同一房间
        // 缓存命中：直接换 URL
        if let hls = hlsCache[room.webRid] {
            play(url: hls, webRid: room.webRid)
            return
        }
        // feed 阶段已带 hls 直接用
        let feedHls = DYLiveClient.bestHlsUrl(room.hlsUrls)
        if !feedHls.isEmpty {
            hlsCache[room.webRid] = feedHls
            play(url: feedHls, webRid: room.webRid)
            return
        }
        // enter resolve（去重防并发）
        guard !resolving.contains(room.webRid) else { return }
        resolving.insert(room.webRid)
        DYLog.shared.log("LIVEFEED resolve idx webRid=\(room.webRid)")
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

    /// 共享 player 换 URL（黑屏关键：AVURLAsset 带 AVURLAssetHTTPHeaderFieldsKey，照 VOD 出画面路径）
    private func play(url: String, webRid: String) {
        guard playingWebRid != webRid, let u = URL(string: url) else { return }
        // 照 VOD NativePlayerView.swift:423：AVURLAsset 带 header（裸 AVPlayerItem 没带 → CDN 返回空 → 黑屏）
        let asset = AVURLAsset(url: u, options: ["AVURLAssetHTTPHeaderFieldsKey": liveHeaders()])
        let item = AVPlayerItem(asset: asset)
        sharedPlayer.replaceCurrentItem(with: item)
        playingWebRid = webRid
        sharedPlayer.play()
        DYLog.shared.event("LIVEFEED play webRid=\(webRid) hls=\(url.prefix(70))")
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
        cell.playerLayerView.frame = cell.contentView.bounds
        cell.coverImageView.frame = cell.contentView.bounds
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        collectionView.bounds.size
    }
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let c = cell as? LivePlayerCell else { return }
        c.playerLayerView.frame = c.contentView.bounds
        c.coverImageView.frame = c.contentView.bounds
        let idx = indexPath.item
        let rooms = DYLiveClient.shared.rooms
        guard rooms.indices.contains(idx) else { return }
        let room = rooms[idx]
        let viewerText = room.userCount.isEmpty ? "" : "\(room.userCount)观看"
        c.configure(room: room, viewerText: viewerText)
        // 封面兜底（未 bind/未 ready 时不黑屏）
        if !room.coverUrl.isEmpty, let cu = URL(string: room.coverUrl) {
            AvatarLoader.shared.load(cu) { [weak c] img in c?.setCover(img) }
        }
        // 居中 cell bind 共享 player 出画面
        if idx == currentIndex {
            c.bind(player: sharedPlayer)
            let ready = (sharedPlayer.currentItem?.status == .readyToPlay)
            c.setCoverVisible(!ready)
            DYLog.shared.log("LIVEFEED willDisplay idx=\(idx) ready=\(ready ? 1 : 0) status=\(sharedPlayer.currentItem?.status.rawValue ?? -1)")
        } else {
            c.unbind()
            c.setCoverVisible(true)
        }
    }
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? LivePlayerCell)?.unbind()
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
