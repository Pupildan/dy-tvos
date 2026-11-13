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

/// Feed Cell：每个 Cell 独占一个 AVPlayer（真实视频图层随 Cell 滑动）。
/// 铁律：真实视频层物理滑动，绝无截图假象。每 Cell 一个解码器，显示哪个 index 就播哪个，
/// 永不 replaceCurrentItem 换 URL——根除"池改派换源空窗"导致的黑屏/冻屏。
final class PlayerCell: UICollectionViewCell {
    let playerView = PlayerLayerView()
    /// 本 Cell 独占的 player（显示期间持有一个，复用时销毁）
    private var player: AVPlayer?
    /// 正在装载的 index（防 recycled cell 串号）
    private var loadedIndex: Int = -1

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

    /// 装载 index 的视频到本 Cell 独占的 player（每次显示都新建，不换 URL）。
    func configure(index: Int, url: URL, cookieHeader: String?) {
        // 彻底销毁旧 player（不 replaceCurrentItem 换源，根除换源空窗）
        teardownPlayer()
        var headers = ["User-Agent": DYFeedClient.mobileUA]
        if let cookie = cookieHeader, !cookie.isEmpty {
            headers["Cookie"] = cookie
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 8
        asset.loadValuesAsynchronously(forKeys: ["playable"])
        let p = AVPlayer()
        p.replaceCurrentItem(with: item)
        p.isMuted = true            // 默认静音，只有居中槽由控制器解除
        playerView.player = p
        player = p
        loadedIndex = index
        DYLog.shared.log("CELL load idx=\(index) player=\(ObjectIdentifier(p).hashValue)")
    }

    /// 播放本 Cell（仅居中槽由控制器调）。
    func play() {
        player?.isMuted = false
        player?.play()
    }
    /// 暂停本 Cell（非居中槽）。
    func pause() {
        player?.pause()
        player?.isMuted = true
    }
    /// 当前时间（seek 用）。
    func currentTime() -> CMTime {
        player?.currentItem?.currentTime() ?? .zero
    }
    func seek(to t: CMTime) {
        player?.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    var isPlaying: Bool {
        player?.timeControlStatus == .playing
    }

    /// 复用时彻底销毁 player（防 recycled cell 串号/黑屏）。
    override func prepareForReuse() {
        super.prepareForReuse()
        teardownPlayer()
        loadedIndex = -1
    }

    private func teardownPlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerView.player = nil
        player = nil
    }
}

/// 原生播放器：UICollectionView 垂直分页 + 每 Cell 独占 AVPlayer。
/// 真实图层滑动：滑动=前后两个 Cell 连同真实视频画面一起位移（UIScrollView 原生物理/惯性）。
/// 每 Cell 一个解码器、显示哪个播哪个、永不换 URL——根除池改派换源空窗（黑屏/冻屏病根）。
/// 遥控：上/下驱动 setContentOffset 滚动；左右=seek；播放暂停键切换。
final class DYPlayerViewController: UIViewController {
    private var cancellables = Set<AnyCancellable>()
    private var collectionView: UICollectionView!
    private var currentIndex = 0
    private var didInitialScroll = false

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
        // 对齐引擎索引 + 接近末尾时翻页（否则刷完首批就卡死）
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
        // 滚动到位：居中 Cell 播、其余停（cell 已在 cellForItemAt 各自装载，此处只控播放态）
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.35 : 0.05)) { [weak self] in
            self?.updatePlaybackStates(center: clampedIndex)
        }
    }

    /// 只有居中 Cell 播放（解除静音），其余暂停+静音。
    /// 每 Cell 独占 player、无换 URL，故无换源空窗——居中槽直接 play，AVPlayer 没 ready 会自己缓冲。
    private func updatePlaybackStates(center index: Int) {
        for cell in collectionView.visibleCells {
            guard let c = cell as? PlayerCell,
                  let ip = collectionView.indexPath(for: c) else { continue }
            if ip.item == index {
                c.play()
            } else {
                c.pause()
            }
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

    private func centeredCell() -> PlayerCell? {
        let ci = centeredIndex()
        for cell in collectionView.visibleCells {
            if let c = cell as? PlayerCell,
               let ip = collectionView.indexPath(for: c), ip.item == ci {
                return c
            }
        }
        return nil
    }

    private func seek(by seconds: Double) {
        guard let c = centeredCell() else { return }
        let t = c.currentTime().seconds
        guard t.isFinite else { return }
        let target = max(0, t + seconds)
        c.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        DYLog.shared.log("FEEDCOLL seek \(seconds)s -> \(target)")
    }
    private func togglePlayPause() {
        guard let c = centeredCell() else { return }
        if c.isPlaying { c.pause() } else { c.play() }
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
        let idx = indexPath.item
        guard PlaybackEngine.shared.urls.indices.contains(idx) else { return cell }
        let url = PlaybackEngine.shared.urls[idx]
        // 每 Cell 独占 player 装载本 index（configure 内部先销毁旧 player，不换 URL）
        cell.configure(index: idx, url: url, cookieHeader: DYFeedClient.shared.cookieHeaderForPlayback())
        cell.playerView.frame = cell.contentView.bounds
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        collectionView.bounds.size
    }
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? PlayerCell)?.playerView.frame = cell.contentView.bounds
    }
    /// tvOS 无 isPagingEnabled：拖拽结束手动整页吸附
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
}

/// SwiftUI 包装：UICollectionView 垂直分页真实视频滑动（每 Cell 独占 AVPlayer）。
struct NativePlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DYPlayerViewController {
        DYPlayerViewController()
    }
    func updateUIViewController(_ uiViewController: DYPlayerViewController, context: Context) {}
}
