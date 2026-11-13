import UIKit
import AVKit
import AVFoundation
import SwiftUI
import Combine

/// 承载单个 AVPlayer 的容器 view：AVPlayerLayer 铺满，供 Cell 持有。
final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
}

/// Feed Cell：内嵌 PlayerLayerView，绑定池里的 AVPlayer（真实视频图层随 Cell 滑动）。
final class PlayerCell: UICollectionViewCell {
    let playerView = PlayerLayerView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        contentView.addSubview(playerView)
        playerView.playerLayer.videoGravity = .resizeAspect   // 居中、不裁切、周围留白
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        playerView.frame = contentView.bounds
    }
}

/// 原生播放器：UICollectionView 垂直分页 + 3 实例 AVPlayer 池。
/// 真实图层滑动：滑动=前后两个 Cell 连同真实视频画面一起位移（UIScrollView 原生物理/惯性），绝无截图假象。
/// PlayerPool 维持 3 个 AVPlayer 循环复用（当前/上一/下一），Cell 划出不销毁，replaceCurrentItem 复用（治 Cannot Open）。
/// 遥控：上/下驱动 setContentOffset 滚动；左右=seek；播放暂停键切换。
final class DYPlayerViewController: UIViewController {
    private var cancellables = Set<AnyCancellable>()
    private var collectionView: UICollectionView!
    private var currentIndex = 0
    private var didInitialScroll = false

    // PlayerPool：3 个循环复用的 AVPlayer
    private lazy var playerPool: [AVPlayer] = (0..<3).map { _ in AVPlayer() }
    /// 每个 player 当前装载的 index（池复用依据）
    private var playerIndex: [AVPlayer: Int] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        view.backgroundColor = .black
        DYLog.shared.log("FEEDCOLL viewDidLoad")

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
        collectionView.register(PlayerCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = false
        view.addSubview(collectionView)

        PlaybackEngine.shared.$urls
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadIfNeeded() }
            .store(in: &cancellables)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.height > 0 else { return }
        collectionView.frame = view.bounds
        if !didInitialScroll, !PlaybackEngine.shared.urls.isEmpty {
            didInitialScroll = true
            scrollTo(index: PlaybackEngine.shared.index, animated: false)
        }
        for cell in collectionView.visibleCells {
            (cell as? PlayerCell)?.playerView.frame = (cell as? PlayerCell)?.contentView.bounds ?? .zero
        }
    }

    private func reloadIfNeeded() {
        guard collectionView.bounds.height > 0, !PlaybackEngine.shared.urls.isEmpty else { return }
        scrollTo(index: PlaybackEngine.shared.index, animated: false)
    }

    // MARK: - 滚动驱动

    /// 目标 index 是否可安全 scrollToItem：collectionView 已 layout、item 数覆盖 index。
    /// 崩溃根因（.ips 堆栈）：首次 urls 到达时 flow layout 未算出 contentSize，
    /// scrollToItem 判定 indexPath 越界 → _validateScrollingTargetIndexPath 抛 NSException → SIGABRT。
    private func canScrollTo(index: Int) -> Bool {
        guard collectionView.bounds.height > 0, collectionView.window != nil else { return false }
        // 强制 layout 让 flow layout 算出真实 contentSize / item 数
        collectionView.layoutIfNeeded()
        let items = collectionView.numberOfItems(inSection: 0)
        return index >= 0 && index < items
    }

    private func scrollTo(index: Int, animated: Bool) {
        guard canScrollTo(index: index) else {
            DYLog.shared.log("FEEDCOLL scrollTo SKIP idx=\(index) (not laid out / idx out of range)")
            return
        }
        let ip = IndexPath(item: index, section: 0)
        collectionView.scrollToItem(at: ip, at: .centeredVertically, animated: animated)
        currentIndex = index
        // 关键：滚动一开始就预载目标±1（不等滚动结束），让滑动时相邻已缓冲不卡
        preloadAdjacent(around: index)
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.35 : 0.05)) { [weak self] in
            self?.updatePlaybackStates(center: index)
        }
    }

    // MARK: - PlayerPool

    /// 取一个 player 装载 index（复用已装载该 index 的；否则取离中心最远的）。
    private func acquirePlayer(for index: Int) -> AVPlayer {
        if let owned = playerPool.first(where: { playerIndex[$0] == index }) {
            return owned
        }
        guard let p = playerPool.min(by: { distance($0) > distance($1) }) else {
            let fb = playerPool[0]
            load(player: fb, index: index)
            return fb
        }
        load(player: p, index: index)
        return p
    }

    private func distance(_ p: AVPlayer) -> Int {
        guard let i = playerIndex[p] else { return Int.max }
        return abs(i - currentIndex)
    }

    private func load(player: AVPlayer, index: Int) {
        guard PlaybackEngine.shared.urls.indices.contains(index) else { return }
        let url = PlaybackEngine.shared.urls[index]
        var headers = ["User-Agent": DYFeedClient.mobileUA]
        if let cookie = DYFeedClient.shared.cookieHeaderForPlayback(), !cookie.isEmpty {
            headers["Cookie"] = cookie
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 8
        asset.loadValuesAsynchronously(forKeys: ["playable"])
        player.replaceCurrentItem(with: item)   // 复用：不销毁 player，仅换 item
        player.isMuted = false
        playerIndex[player] = index
        DYLog.shared.log("POOL load idx=\(index)")
    }

    /// 只有居中 cell 播放，其余暂停；并预载相邻。
    private func updatePlaybackStates(center index: Int) {
        for p in playerPool {
            guard let pi = playerIndex[p] else { continue }
            if pi == index { p.play() } else { p.pause() }
        }
        for adj in [index - 1, index + 1] where adj >= 0 {
            if !playerPool.contains(where: { playerIndex[$0] == adj }),
               let free = playerPool.first(where: { p in
                   guard let i = playerIndex[p] else { return true }
                   return abs(i - index) > 1
               }) {
                load(player: free, index: adj)
            }
        }
    }

    /// 预载 index 及其相邻（上一/下一）的 player，让滑动时已缓冲。
    private func preloadAdjacent(around index: Int) {
        for i in [index - 1, index, index + 1] where i >= 0 {
            acquirePlayer(for: i)
        }
    }

    /// 当前居中的 item index。
    private func centeredIndex() -> Int {
        guard collectionView.bounds.height > 0 else { return currentIndex }
        let center = CGPoint(x: collectionView.bounds.midX, y: collectionView.bounds.midY)
        if let ip = collectionView.indexPathForItem(at: center) { return ip.item }
        return Int(round(collectionView.contentOffset.y / max(1, collectionView.bounds.height)))
    }

    private func advance() {
        scrollTo(index: centeredIndex() + 1, animated: true)
    }
    private func rewind() {
        scrollTo(index: max(0, centeredIndex() - 1), animated: true)
    }

    private func seek(by seconds: Double) {
        let p = playerForCentered()
        guard let t = p?.currentItem?.currentTime().seconds, t.isFinite else { return }
        let target = max(0, t + seconds)
        p?.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        DYLog.shared.log("FEEDCOLL seek \(seconds)s -> \(target)")
    }
    private func playerForCentered() -> AVPlayer? {
        let ci = centeredIndex()
        return playerPool.first { playerIndex[$0] == ci }
    }
    private func togglePlayPause() {
        guard let p = playerForCentered() else { return }
        if p.timeControlStatus == .playing { p.pause() } else { p.play() }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .downArrow: advance(); return
            case .upArrow: rewind(); return
            case .leftArrow: seek(by: -10); return
            case .rightArrow: seek(by: 10); return
            case .playPause: togglePlayPause(); return
            default: break
            }
        }
        super.pressesBegan(presses, with: event)
    }
}

extension DYPlayerViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        PlaybackEngine.shared.urls.count
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! PlayerCell
        let p = acquirePlayer(for: indexPath.item)
        cell.playerView.player = p
        cell.playerView.frame = cell.contentView.bounds
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        collectionView.bounds.size
    }
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? PlayerCell)?.playerView.frame = cell.contentView.bounds
    }
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // Cell 划出屏幕：暂停其 player（不销毁，放回池循环复用）
        if let c = cell as? PlayerCell, let p = c.playerView.player {
            p.pause()
            DYLog.shared.log("POOL pause offscreen idx=\(indexPath.item)")
        }
    }
    /// tvOS 无 isPagingEnabled：拖拽结束手动整页吸附
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, withTargetContentOffset targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let pageHeight = max(1, scrollView.bounds.height)
        let targetY = targetContentOffset.pointee.y
        let snappedY = (velocity.y >= 0 ? ceil(targetY / pageHeight) : floor(targetY / pageHeight)) * pageHeight
        targetContentOffset.pointee.y = snappedY
    }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        let ci = centeredIndex()
        updatePlaybackStates(center: ci)
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let ci = centeredIndex()
        updatePlaybackStates(center: ci)
    }
}

/// SwiftUI 包装：UICollectionView 垂直分页真实视频滑动。
struct NativePlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DYPlayerViewController {
        DYPlayerViewController()
    }
    func updateUIViewController(_ uiViewController: DYPlayerViewController, context: Context) {}
}
