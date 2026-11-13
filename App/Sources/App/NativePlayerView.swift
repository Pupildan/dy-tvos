import UIKit
import AVKit
import AVFoundation
import SwiftUI
import Combine

/// 承载单个 AVPlayer 的容器 view：AVPlayerLayer 铺满，供 Cell 复用。
final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
}

/// Feed Cell：内嵌 PlayerLayerView，被复用时绑定池里的 AVPlayer。
final class PlayerCell: UICollectionViewCell {
    let playerView = PlayerLayerView()
    var currentIndex: Int = -1

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        contentView.addSubview(playerView)
        playerView.frame = contentView.bounds
        playerView.playerLayer.videoGravity = .resizeAspect   // 居中、不裁切、周围留白
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        playerView.frame = contentView.bounds
    }
}

/// 原生播放器：UICollectionView 垂直分页 + 3 实例 AVPlayer 池。
/// 真实图层滑动：滑动=前后两个 Cell 连同真实视频画面一起位移（UIScrollView 原生物理/惯性），
/// 绝无截图/PPT 假象。PlayerPool 维持 3 个 AVPlayer 循环复用（当前/上一/下一），
/// Cell 划出屏幕不销毁播放器，replaceCurrentItem 复用，彻底规避 Cannot Open。
/// 遥控：上/下驱动 setContentOffset 滚动；左右=seek；播放暂停键切换。
final class DYPlayerViewController: UIViewController {
    private var cancellables = Set<AnyCancellable>()
    private var collectionView: UICollectionView!
    private var currentIndex = 0

    // PlayerPool：3 个循环复用的 AVPlayer（当前/上一/下一）
    private lazy var playerPool: [AVPlayer] = (0..<3).map { _ in
        let p = AVPlayer()
        p.isMuted = false
        return p
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
        collectionView.isPagingEnabled = true
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

        // 首次 urls 到达后滚到 index 0 并播放
        PlaybackEngine.shared.$index
            .receive(on: DispatchQueue.main)
            .sink { [weak self] idx in
                guard let self, self.collectionView.bounds.height > 0 else { return }
                self.scrollTo(index: idx, animated: false)
            }
            .store(in: &cancellables)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.frame = view.bounds
        // 布局变化后刷新可见 cell 的 playerLayer frame
        for cell in collectionView.visibleCells {
            (cell as? PlayerCell)?.playerView.frame = (cell as? PlayerCell)?.contentView.bounds ?? .zero
        }
    }

    private func reloadIfNeeded() {
        guard collectionView.bounds.height > 0, !PlaybackEngine.shared.urls.isEmpty else { return }
        scrollTo(index: PlaybackEngine.shared.index, animated: false)
    }

    // MARK: - PlayerPool 装载

    /// 从池里取一个"空闲或最远"的 player 装载 index 的内容。
    private func acquirePlayer(for index: Int) -> AVPlayer {
        // 若某 player 已装载该 index，直接复用（避免 replaceCurrentItem 抖动）
        if let owned = playerPool.first(where: { playerForIndex[$0] == index }) {
            return owned
        }
        // 否则取"离当前播放最远/未播放"的 player
        let p = (playerPool.min { distanceFromCenter($0) > distanceFromCenter($1) })
        load(player: p, index: index)
        return p
    }

    /// 记录每个 player 当前装载的 index（池复用依据）。
    private var playerForIndex: [AVPlayer: Int] = [:]
    private func distanceFromCenter(_ p: AVPlayer) -> Int {
        guard let i = playerForIndex[p] else { return Int.max }
        return abs(i - currentIndex)
    }

    private func load(player: AVPlayer, index: Int) {
        guard let url = PlaybackEngine.shared.urls.indices.contains(index) ? PlaybackEngine.shared.urls[index] : nil else { return }
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
        playerForIndex[player] = index
        DYLog.shared.log("POOL load idx=\(index) -> \(url.absoluteString.prefix(60))")
    }

    /// 只有居中 cell 播放，其余暂停（省资源，且不会多路出声）。
    private func updatePlaybackStates(center index: Int) {
        for p in playerPool {
            guard let pi = playerForIndex[p] else { continue }
            if pi == index { p.play() } else { p.pause() }
        }
        // 预载相邻（上一/下一），让滑动到时已缓冲
        for adj in [index - 1, index + 1] where adj >= 0 {
            if !playerPool.contains(where: { playerForIndex[$0] == adj }) {
                // 用空闲 player 预载相邻
                if let free = playerPool.first(where: { p in
                    guard let i = playerForIndex[p] else { return true }
                    return abs(i - index) > 1
                }) {
                    load(player: free, index: adj)
                }
            }
        }
        DYLog.shared.log("FEEDCOLL center=\(index) states=\(playerPool.map { "\(playerForIndex[$0] ?? -1):\($0.timeControlStatus == .playing ? "P" : "Pz")" }.joined(separator: ","))")
    }

    // MARK: - 滚动驱动

    private func scrollTo(index: Int, animated: Bool) {
        guard index >= 0, index < PlaybackEngine.shared.urls.count else { return }
        let ip = IndexPath(item: index, section: 0)
        collectionView.scrollToItem(at: ip, at: .centeredVertically, animated: animated)
        currentIndex = index
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.35 : 0.05)) { [weak self] in
            self?.updatePlaybackStates(center: index)
        }
    }

    /// 当前居中的 item index。
    private func centeredIndex() -> Int {
        let center = CGPoint(x: collectionView.bounds.midX, y: collectionView.bounds.midY)
        if let ip = collectionView.indexPathForItem(at: center) { return ip.item }
        let page = Int(round(collectionView.contentOffset.y / max(1, collectionView.bounds.height)))
        return page
    }

    private func advance() {
        let cur = centeredIndex()
        scrollTo(index: cur + 1, animated: true)
    }
    private func rewind() {
        let cur = centeredIndex()
        scrollTo(index: max(0, cur - 1), animated: true)
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
        return playerPool.first { playerForIndex[$0] == ci }
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
        cell.currentIndex = indexPath.item
        // 从池里取 player 绑定到这个 cell（真实视频图层随 cell 滑动）
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
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        let ci = centeredIndex()
        updatePlaybackStates(center: ci)
        PlaybackEngine.shared.index = ci
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let ci = centeredIndex()
        updatePlaybackStates(center: ci)
        PlaybackEngine.shared.index = ci
    }
}

/// SwiftUI 包装：UICollectionView 垂直分页真实视频滑动。
struct NativePlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DYPlayerViewController {
        DYPlayerViewController()
    }
    func updateUIViewController(_ uiViewController: DYPlayerViewController, context: Context) {}
}
