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
    /// 每个 player 的 currentItem.status KVO（ready 了才 play，治"有声画面冻结"）
    private var statusObservers: [AVPlayer: NSKeyValueObservation] = [:]

    deinit {
        for obs in statusObservers.values { obs.invalidate() }
    }

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
        guard !PlaybackEngine.shared.urls.isEmpty else { return }
        // urls 变化后必须 reloadData，flow layout 才会真正建 cell（否则 numberOfItems 恒 0 → scrollTo 全 SKIP → 黑屏）
        collectionView.reloadData()
        scrollTo(index: PlaybackEngine.shared.index, animated: false)
    }

    // MARK: - 滚动驱动

    /// 是否具备滚动条件：有数据 + 已进 window + bounds 有效。满足时 reloadData/layout 后可安全滚动。
    private func canScrollTo(index: Int) -> Bool {
        guard collectionView.window != nil,
              collectionView.bounds.height > 0,
              !PlaybackEngine.shared.urls.isEmpty else { return false }
        // 强制 layout 让 flow layout 算出真实 contentSize
        collectionView.layoutIfNeeded()
        return true
    }

    private func scrollTo(index: Int, animated: Bool) {
        guard canScrollTo(index: index) else {
            DYLog.shared.log("FEEDCOLL scrollTo SKIP idx=\(index) (not laid out / no data)")
            return
        }
        let count = PlaybackEngine.shared.urls.count
        guard index >= 0, index < count else { return }
        let clampedIndex = min(max(0, index), count - 1)
        // 用 setContentOffset（clamp 到 contentSize 内）替代 scrollToItem：
        // 后者在 flow layout 未就绪时会走 _validateScrollingTargetIndexPath 抛 NSException（.ips 已定位）。
        let pageHeight = max(1, collectionView.bounds.height)
        let maxOffset = max(0, collectionView.contentSize.height - collectionView.bounds.height)
        let targetY = min(CGFloat(clampedIndex) * pageHeight, maxOffset)
        collectionView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
        currentIndex = clampedIndex
        // 立刻暂停非目标 player（不等动画/回调）——快速连刷时旧画面会冻住、声音照放（交接文档§声画同步）
        for p in playerPool {
            guard let pi = playerIndex[p] else { continue }
            if pi != clampedIndex { p.pause() }
        }
        // 对齐引擎索引 + 接近末尾时翻页（否则刷完首批就卡死，日志已证：items 恒 6、永不 needMore）
        // 用 next()/prev() 逐步对齐（内部会更新 currentAwemeId，且它们是 private 不能直接赋值）
        let engine = PlaybackEngine.shared
        if clampedIndex > engine.index {
            for _ in engine.index..<clampedIndex { engine.next() }
        } else if clampedIndex < engine.index {
            for _ in clampedIndex..<engine.index { engine.prev() }
        }
        if engine.count > 0, clampedIndex >= engine.count - 7 {
            engine.triggerNeedMore()
        }
        DYLog.shared.log("FEEDCOLL scrollTo idx=\(clampedIndex) y=\(targetY) items=\(count)")
        // 关键：滚动一开始就预载目标±1（不等滚动结束），让滑动时相邻已缓冲不卡
        preloadAdjacent(around: clampedIndex)
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.35 : 0.05)) { [weak self] in
            self?.updatePlaybackStates(center: clampedIndex)
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
        // 换 item 瞬间先静音+暂停：视频轨道未解码前若继续放，会画面冻旧帧、声音已是新视频（冻结+有声根因）
        player.pause()
        player.isMuted = true
        playerIndex[player] = index
        // KVO 等 item 真正 readyToPlay 且它仍是当前居中槽才 play——固定延时赌不准解码时机（有声画面冻结真根因）
        statusObservers[player]?.invalidate()
        statusObservers[player] = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            guard let self, it.status == .readyToPlay else { return }
            DispatchQueue.main.async {
                guard self.playerIndex[player] == index,
                      self.currentIndex == index else { return }
                player.isMuted = false
                player.play()
                DYLog.shared.log("POOL readyPlay idx=\(index)")
            }
        }
        DYLog.shared.log("POOL load idx=\(index)")
    }

    /// 只有居中 cell 播放（解除静音），其余暂停+静音；并预载相邻。
    private func updatePlaybackStates(center index: Int) {
        for p in playerPool {
            guard let pi = playerIndex[p] else { continue }
            if pi == index {
                // 只在 item 已 readyToPlay 时才 play；未 ready 交给 load 里的 KVO（对没解码好的 item 调 play→有声画面冻结）
                if p.currentItem?.status == .readyToPlay {
                    p.isMuted = false   // 居中槽解除静音（load 时置 true，此处恢复出声）
                    p.play()
                }
            } else {
                p.pause()
                p.isMuted = true
            }
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
