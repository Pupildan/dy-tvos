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

/// Feed Cell：不自己创建 Player。willDisplay 时向 PlayerManager 申请绑定对应的 Player 层。
/// 未就绪时显示高清封面 CoverImageView 兜底（绝不强行 play），避免黑屏。
final class PlayerCell: UICollectionViewCell {
    let playerLayerView = PlayerLayerView()
    /// 高清封面兜底：player 未 ready 时显示，绝不黑屏
    let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.backgroundColor = .black
        iv.isHidden = true
        return iv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        contentView.addSubview(playerLayerView)
        contentView.addSubview(coverImageView)
        playerLayerView.playerLayer.videoGravity = .resizeAspect
        // 焦点隔离实验：把 cell 彻底排除出 tvOS 焦点系统，验证跳多页是否焦点引擎作怪
        isUserInteractionEnabled = false
    }
    override var canBecomeFocused: Bool { false }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayerView.frame = contentView.bounds
        coverImageView.frame = contentView.bounds
    }

    /// 绑定 PlayerManager 分配的 player（Cell 不创建、不持有 player 生命周期）。
    func bind(player: AVPlayer) {
        playerLayerView.player = player
    }
    /// 设置封面兜底图。
    func setCover(_ image: UIImage?) {
        coverImageView.image = image
    }
    /// 封面显隐：player 未 ready 时显示封面，ready 后隐藏露出真实视频层。
    func setCoverVisible(_ visible: Bool) {
        coverImageView.isHidden = !visible
    }
}

/// 全局唯一 Player 管理器：最多维护 3 个 AVPlayer（current-1 / current / current+1）。
/// 按需分配 + 按距离驱逐：超出 [idx-1, idx+1] 的 player 立刻 pause + replaceCurrentItem(nil)，
/// 强制系统瞬间回收解码器——根治"解码器耗尽→黑屏"。Cell 不创建 player，只绑定。
final class PlayerManager {
    static let shared = PlayerManager()
    /// 上限池：index -> AVPlayer
    private var players: [Int: AVPlayer] = [:]
    /// index -> 封面图（异步生成后缓存，未 ready 时兜底）
    private var covers: [Int: UIImage] = [:]
    private var coversLoading = Set<Int>()
    /// player ready 变化回调（index）——供控制器刷新封面显隐
    var onPlayerReady: ((Int) -> Void)?
    private var readyObservers: [Int: NSKeyValueObservation] = [:]
    /// 已跳过的失败 index——只 skip 一次，防反复 acquire/failed 驱动 advance 级联跳多页
    private var failedIndices = Set<Int>()

    private init() {}

    /// 滑动到 idx：确保 [idx-2, idx+2] 有 player，驱逐范围外的（pause + 置空 item 回收解码器）。
    /// 窗口放宽到 ±2：来回微抖时有缓冲余量，不会一抖就 evict 刚 ready 的（±1 会抖动→黑屏）。
    /// 只从 scrollTo(最终目标 index) 调用；updatePlaybackStates/willDisplay 只查池不触驱逐（杜绝双 center 打架抖动）。
    func prepare(center idx: Int) {
        // desired 窗口跳过已失败的 index（坏视频不再 acquire/failed，断级联跳多页），按顺序取最多 5 个
        let window = (idx - 2...idx + 2).filter { $0 >= 0 && PlaybackEngine.shared.urls.indices.contains($0) && !failedIndices.contains($0) }
        let desired = Array(window.prefix(5))
        // 1) 驱逐范围外的 player：pause + replaceCurrentItem(nil) 强制回收解码器
        for (i, p) in players where !desired.contains(i) {
            p.pause()
            p.replaceCurrentItem(with: nil)   // 关键：置空 item，系统瞬间回收解码器
            readyObservers[i]?.invalidate()
            readyObservers.removeValue(forKey: i)
            players.removeValue(forKey: i)
            DYLog.shared.log("MGR evict idx=\(i)")
        }
        // 2) 确保范围内的都存在（复用已有，缺失才建）
        for i in desired where players[i] == nil {
            acquire(index: i)
        }
    }

    /// 取 index 的 player（prepare 已确保存在；防御性：缺失则现建）。
    func player(at index: Int) -> AVPlayer? {
        if let p = players[index] { return p }
        guard PlaybackEngine.shared.urls.indices.contains(index) else { return nil }
        return acquire(index: index)
    }

    /// 纯查询（不 acquire、不驱逐）：池里有就返回，没有返回 nil。willDisplay 用它，避免快速滑动撑大池。
    func peekPlayer(at index: Int) -> AVPlayer? {
        players[index]
    }

    /// index 的封面兜底图（异步生成，未就绪返回 nil，生成完回调刷新）。
    func cover(at index: Int, completion: @escaping (UIImage?) -> Void) {
        if let img = covers[index] { completion(img); return }
        guard PlaybackEngine.shared.urls.indices.contains(index) else { completion(nil); return }
        if coversLoading.contains(index) { completion(nil); return }
        coversLoading.insert(index)
        let url = PlaybackEngine.shared.urls[index]
        var headers = ["User-Agent": DYFeedClient.mobileUA]
        if let cookie = DYFeedClient.shared.cookieHeaderForPlayback(), !cookie.isEmpty {
            headers["Cookie"] = cookie
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1080, height: 1920)
        gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime.zero)]) { [weak self] _, cg, _, result, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.coversLoading.remove(index)
                guard result == .succeeded, let cg else { completion(nil); return }
                let img = UIImage(cgImage: cg)
                self.covers[index] = img
                completion(img)
            }
        }
    }

    /// 新建 player 装载 index，挂 ready KVO（ready 时回调刷新封面显隐）。
    private func acquire(index: Int) -> AVPlayer {
        let url = PlaybackEngine.shared.urls[index]
        var headers = ["User-Agent": DYFeedClient.mobileUA]
        if let cookie = DYFeedClient.shared.cookieHeaderForPlayback(), !cookie.isEmpty {
            headers["Cookie"] = cookie
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 8
        let p = AVPlayer()
        p.replaceCurrentItem(with: item)
        players[index] = p
        readyObservers[index]?.invalidate()
        readyObservers[index] = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            // ready → 回调刷新封面；failed(Cannot Open，如 HEVC 解不出) → 预处理无感跳过
            guard it.status == .readyToPlay || it.status == .failed else { return }
            let failed = (it.status == .failed)
            DispatchQueue.main.async {
                if failed {
                    DYLog.shared.log("MGR failed idx=\(index) err=\(it.error?.localizedDescription ?? "?") -> skip")
                    self?.skipFailed(index: index)
                } else {
                    // readyToPlay 但无视频轨 = 图集/纯音频（黑屏无声）→ 也跳过
                    if it.tracks(withMediaType: .video).isEmpty {
                        DYLog.shared.log("MGR ready idx=\(index) 但无视频轨 -> skip")
                        self?.skipFailed(index: index)
                        return
                    }
                    self?.onPlayerReady?(index)
                    DYLog.shared.log("MGR ready idx=\(index)")
                }
            }
        }
        DYLog.shared.log("MGR acquire idx=\(index) total=\(players.count)")
        return p
    }

    /// 预处理无感跳过：index 的视频打不开(Cannot Open，如 HEVC 解不出)时，驱逐它并回调跳过。
    /// 只对首次失败回调 advance：failedIndices 记录已跳过的，重复 failed 不再 advance（断级联跳多页）。
    func skipFailed(index: Int) {
        if let p = players[index] {
            p.pause()
            p.replaceCurrentItem(with: nil)
            readyObservers[index]?.invalidate()
            readyObservers.removeValue(forKey: index)
            players.removeValue(forKey: index)
        }
        guard !failedIndices.contains(index) else {
            DYLog.shared.log("MGR failed idx=\(index) dup -> no advance (break cascade)")
            return
        }
        failedIndices.insert(index)
        onSkipFailed?(index)
    }

    /// 失败跳过回调（index）——控制器接到后 advance 到下一个。
    var onSkipFailed: ((Int) -> Void)?
}

/// 原生播放器：UICollectionView 垂直分页 + PlayerManager 上限 3 池。
/// 真实图层滑动（铁律）：滑动=前后 Cell 连同真实视频画面一起位移（UIScrollView 原生物理）。
/// 解码器上限 3（current±1）+ 超范围驱逐回收 → 根治解码器耗尽黑屏；未就绪显示封面兜底 → 无黑屏。
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
        // player ready → 刷新可见 cell 封面显隐（ready 的隐藏封面露出真实视频）
        PlayerManager.shared.onPlayerReady = { [weak self] idx in
            self?.refreshCoverForVisible()
        }
        // player 打不开(Cannot Open/HEVC) → 预处理无感跳过：仅当失败的是当前居中才 advance（邻位预载失败不跳）
        PlayerManager.shared.onSkipFailed = { [weak self] idx in
            guard idx == self?.currentIndex else { return }
            DYLog.shared.log("FEEDCOLL skip failed idx=\(idx) -> advance")
            self?.advance()
        }
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
            (cell as? PlayerCell)?.playerLayerView.frame = (cell as? PlayerCell)?.contentView.bounds ?? .zero
            (cell as? PlayerCell)?.coverImageView.frame = (cell as? PlayerCell)?.contentView.bounds ?? .zero
        }
    }

    private var lastKnownCount = 0

    private func reloadIfNeeded() {
        let newCount = PlaybackEngine.shared.urls.count
        guard newCount > 0 else { return }
        let oldCount = lastKnownCount
        if oldCount == 0 {
            // 首批：全量建池（一次性）
            collectionView.reloadData()
            lastKnownCount = newCount
            scrollTo(index: PlaybackEngine.shared.index, animated: false)
            return
        }
        guard newCount > oldCount else { return }
        // 翻页增量插入：只插入新增的 index，不动已有 cell/player 池（避免 reloadData 全量重建
        // 摧毁已缓冲 player → 居中瞬黑屏，且刷越多页 merge 越频繁黑屏概率越大）
        var newIdx: [IndexPath] = []
        for i in oldCount..<newCount { newIdx.append(IndexPath(item: i, section: 0)) }
        collectionView.performBatchUpdates({
            collectionView.insertItems(at: newIdx)
        }, completion: nil)
        lastKnownCount = newCount
        // 引擎 index 已在新增范围外时（罕见）校正，正常翻页 index 落在已有区间无需滚动
        let idx = PlaybackEngine.shared.index
        if idx >= newCount {
            scrollTo(index: newCount - 1, animated: false)
        }
    }

    // MARK: - 滚动驱动

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
        // setContentOffset 替代 scrollToItem（后者 flow layout 未就绪会抛 NSException，.ips 已定位）
        let pageHeight = max(1, collectionView.bounds.height)
        let maxOffset = max(0, collectionView.contentSize.height - collectionView.bounds.height)
        let targetY = min(CGFloat(clampedIndex) * pageHeight, maxOffset)
        collectionView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
        currentIndex = clampedIndex
        // 对齐引擎索引 + 接近末尾翻页
        let engine = PlaybackEngine.shared
        if clampedIndex > engine.index {
            for _ in engine.index..<clampedIndex { engine.next() }
        } else if clampedIndex < engine.index {
            for _ in clampedIndex..<engine.index { engine.prev() }
        }
        if engine.count > 0, clampedIndex >= engine.count - 7 {
            engine.triggerNeedMore()
        }
        // 核心：让 PlayerManager 只保留 [idx-1, idx+1] 三个 player，超范围驱逐回收解码器
        PlayerManager.shared.prepare(center: clampedIndex)
        DYLog.shared.log("FEEDCOLL scrollTo idx=\(clampedIndex) y=\(targetY) items=\(count)")
        // 滚动到位刷新播放态 + 封面显隐
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.35 : 0.05)) { [weak self] in
            self?.updatePlaybackStates(center: clampedIndex)
        }
    }

    /// 居中 Cell 播放（player 已 ready），非居中暂停；未 ready 的显示封面兜底，绝不强行 play。
    /// 不调 prepare（那会用 centeredIndex 和 scrollTo 的目标 index 打架→池抖动→黑屏）；只查池控播放态。
    private func updatePlaybackStates(center index: Int) {
        for cell in collectionView.visibleCells {
            guard let c = cell as? PlayerCell,
                  let ip = collectionView.indexPath(for: c) else { continue }
            let idx = ip.item
            let isCenter = (idx == index)
            if let p = PlayerManager.shared.player(at: idx) {
                c.bind(player: p)
                let ready = (p.currentItem?.status == .readyToPlay)
                if isCenter, ready {
                    p.play()
                    c.setCoverVisible(false)
                } else {
                    p.pause()
                    // 未 ready（或非居中）显示封面兜底
                    if !ready { loadCover(for: c, index: idx) }
                    c.setCoverVisible(!ready)
                }
            } else {
                // 无 player（超范围）：显示封面兜底
                loadCover(for: c, index: idx)
                c.setCoverVisible(true)
            }
        }
    }

    /// 异步取封面兜底图（未就绪时不黑屏）。
    private func loadCover(for cell: PlayerCell, index: Int) {
        PlayerManager.shared.cover(at: index) { [weak cell] img in
            cell?.setCover(img)
        }
    }

    /// player ready 回调：隐藏对应可见 cell 的封面，露出真实视频。
    private func refreshCoverForVisible() {
        for cell in collectionView.visibleCells {
            guard let c = cell as? PlayerCell,
                  let ip = collectionView.indexPath(for: c),
                  let p = PlayerManager.shared.player(at: ip.item) else { continue }
            if p.currentItem?.status == .readyToPlay {
                c.setCoverVisible(false)
                if ip.item == currentIndex { p.play() }
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

    private func seek(by seconds: Double) {
        guard let p = PlayerManager.shared.player(at: centeredIndex()),
              let t = p.currentItem?.currentTime().seconds, t.isFinite else { return }
        let target = max(0, t + seconds)
        p.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        DYLog.shared.log("FEEDCOLL seek \(seconds)s -> \(target)")
    }
    private func togglePlayPause() {
        guard let p = PlayerManager.shared.player(at: centeredIndex()) else { return }
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
        cell.playerLayerView.frame = cell.contentView.bounds
        cell.coverImageView.frame = cell.contentView.bounds
        // Cell 不创建 player；willDisplay 阶段由 PlayerManager 分配绑定（此处先占位，willDisplay 再绑）
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        collectionView.bounds.size
    }
    /// willDisplay：向 PlayerManager 申请绑定对应 player + 封面兜底
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let c = cell as? PlayerCell else { return }
        c.playerLayerView.frame = c.contentView.bounds
        c.coverImageView.frame = c.contentView.bounds
        let idx = indexPath.item
        // peekPlayer 纯查询不 acquire——避免快速滑动时 willDisplay 把池撑大（抖动→黑屏）
        if let p = PlayerManager.shared.peekPlayer(at: idx) {
            c.bind(player: p)
            let ready = (p.currentItem?.status == .readyToPlay)
            c.setCoverVisible(!ready)
            if !ready { loadCover(for: c, index: idx) }
        } else {
            c.setCoverVisible(true)
            loadCover(for: c, index: idx)
        }
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
}

/// SwiftUI 包装：UICollectionView 垂直分页真实视频滑动（PlayerManager 上限 3 池）。
struct NativePlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DYPlayerViewController {
        DYPlayerViewController()
    }
    func updateUIViewController(_ uiViewController: DYPlayerViewController, context: Context) {}
}
