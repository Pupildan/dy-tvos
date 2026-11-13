import UIKit
import AVKit
import AVFoundation
import SwiftUI
import Combine

/// 双播放器槽位：容器 UIView（内嵌 AVPlayerLayer）+ 封面兜底 UIImageView。
/// 内存/竞态纪律（根治 Cannot Open 死锁 + 黑帧）：
///   1) 前台播放时，后台槽只静音预载（isMuted=true），绝不瞬间同时建两个解码器
///   2) 只有滑入槽 readyToPlay 才起步滑动；未 ready 用封面兜底，绝不黑屏
///   3) 滑动完成后旧槽 pause，延迟 0.5s 错峰 clear（只清非相邻槽，相邻保留供回切）
final class DYPlayerSlot {
    let player: AVPlayer
    let container: UIView
    private let coverImage: UIImageView
    private let layer: AVPlayerLayer
    private(set) var index: Int = -1
    private(set) var isReady = false
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    var currentItem: AVPlayerItem? { player.currentItem }
    /// 封面兜底图（滑动起步时防黑帧，视频层出帧后被盖住）
    var cover: UIImage? {
        get { coverImage.image }
        set { coverImage.image = newValue }
    }

    init() {
        player = AVPlayer()
        container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        coverImage = UIImageView()
        coverImage.contentMode = .scaleAspectFit
        coverImage.clipsToBounds = true
        layer = AVPlayerLayer()
        layer.player = player
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = UIColor.black.cgColor
        container.addSubview(coverImage)
        container.layer.addSublayer(layer)
    }

    func layout(in bounds: CGRect) {
        container.frame = bounds
        coverImage.frame = container.bounds
        layer.frame = container.bounds
    }

    /// 装载 index。muted=true 后台预载；封面图可先兜底。
    func load(url: URL, index: Int, muted: Bool, cover: UIImage?, onReady: @escaping () -> Void, onFailed: @escaping () -> Void) {
        self.index = index
        isReady = false
        removeAllObservers()
        coverImage.image = cover
        var headers = ["User-Agent": DYFeedClient.mobileUA]
        if let cookie = DYFeedClient.shared.cookieHeaderForPlayback(), !cookie.isEmpty {
            headers["Cookie"] = cookie
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 3.0
        asset.loadValuesAsynchronously(forKeys: ["playable"])
        player.replaceCurrentItem(with: item)
        player.isMuted = muted

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            guard let self, self.player.currentItem === it else { return }
            switch it.status {
            case .readyToPlay:
                self.isReady = true
                DYLog.shared.log("SLOT idx=\(index) ready muted=\(self.player.isMuted)")
                onReady()
            case .failed:
                DYLog.shared.log("SLOT idx=\(index) FAILED err=\(it.error?.localizedDescription ?? "?")")
                onFailed()
            default:
                break
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            guard let self, self.player.currentItem === item else { return }
            onFailed()
        }
    }

    /// 错峰释放：pause 后延迟 clear，避免 A12 瞬间同时建/拆两个解码器死锁。
    func pauseAndReleaseLater(delay: TimeInterval) {
        player.pause()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.clear()
        }
    }

    func clear() {
        removeAllObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        index = -1
        isReady = false
        coverImage.image = nil
        DYLog.shared.log("SLOT cleared")
    }

    func removeAllObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = nil
    }

    deinit { removeAllObservers() }
}

/// 原生播放器：双播放器池 + 真实双视频图层同时垂直滑动（抖音式连贯过渡）。
/// 下=当前往上出、下一个从下滑入；上=当前往下出、上一个从上滑入。两图层同时位移，连贯无黑屏。
/// 就绪门控：滑入槽 readyToPlay 才起步；错峰释放：完成后旧槽 pause + 延迟 clear。
final class DYPlayerViewController: UIViewController {
    private var cancellables = Set<AnyCancellable>()
    private let slotA = DYPlayerSlot()
    private let slotB = DYPlayerSlot()
    private lazy var slots: [DYPlayerSlot] = [slotA, slotB]
    private var activeIdx = 0
    private var currentIndex = 0
    private var isAnimating = false

    private var activeSlot: DYPlayerSlot { slots[activeIdx] }
    private var standbySlot: DYPlayerSlot { slots[1 - activeIdx] }
    private var screenHeight: CGFloat { view.bounds.height }

    override func viewDidLoad() {
        super.viewDidLoad()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        view.backgroundColor = .black
        DYLog.shared.log("DUAL viewDidLoad")
        for s in slots {
            s.container.frame = view.bounds
            view.addSubview(s.container)
        }
        slotA.container.transform = .identity
        slotB.container.transform = CGAffineTransform(translationX: 0, y: screenHeight)
        PlaybackEngine.shared.$urls
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadIfNeeded() }
            .store(in: &cancellables)
        reloadIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.height > 0 else { return }
        for s in slots { s.layout(in: view.bounds) }
    }

    private func itemURL(at index: Int) -> URL? {
        PlaybackEngine.shared.urls.indices.contains(index) ? PlaybackEngine.shared.urls[index] : nil
    }

    private func reloadIfNeeded() {
        guard view.bounds.height > 0 else { return }
        guard PlaybackEngine.shared.index != currentIndex else { return }
        guard let url = itemURL(at: PlaybackEngine.shared.index) else { return }
        let target = PlaybackEngine.shared.index
        let outgoing = activeSlot
        let incoming = standbySlot
        currentIndex = target
        // 滑入槽装载（后台静音预载），封面先兜底为 nil（滑动起步不依赖快照）
        incoming.load(url: url, index: target, muted: true, cover: nil, onReady: { [weak self] in
            guard let self else { return }
            // 滑入槽就绪 → 起步真实双图层滑动
            self.slideTo(incoming, index: target, outgoing: outgoing)
        }, onFailed: { [weak self] in
            guard let self else { return }
            DYLog.shared.log("DUAL preload failed idx=\(target)")
        })
        // 异步截当前前台帧 → 填入滑入槽封面兜底（滑入槽视频层未必立刻出帧，封面防黑）
        captureSnapshotOfCurrent { [weak self] img in
            guard let self, self.activeSlot !== incoming else { return }
            incoming.cover = img
        }
    }

    /// 异步截当前前台视频当前帧（不卡主线程），作为滑入槽封面兜底。
    private func captureSnapshotOfCurrent(completion: @escaping (UIImage?) -> Void) {
        guard let item = activeSlot.player.currentItem,
              let asset = item.asset as? AVURLAsset else {
            completion(nil)
            return
        }
        let time = activeSlot.player.currentTime()
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1080, height: 1920)
        gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cg, _, result, _ in
            let img = (result == .succeeded) ? cg.flatMap { UIImage(cgImage: $0) } : nil
            DispatchQueue.main.async { completion(img) }
        }
    }

    // MARK: - 真实双图层滑动

    private func slideTo(_ incoming: DYPlayerSlot, index: Int, outgoing: DYPlayerSlot) {
        guard !isAnimating else { return }
        isAnimating = true
        view.layoutIfNeeded()
        let h = screenHeight
        let down = (index >= outgoing.index)   // 下一个=从下滑入；上一个=从上滑入

        // 起步位置：下一个从下方来，上一个从上方来
        incoming.container.transform = CGAffineTransform(translationX: 0, y: down ? h : -h)
        view.bringSubviewToFront(incoming.container)
        // 滑入槽出声（此刻已 ready）
        incoming.player.isMuted = false
        incoming.player.play()

        DYLog.shared.log("DUAL slide \(down ? "next" : "prev") -> idx=\(index)")
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut]) { [weak self] in
            guard let self else { return }
            incoming.container.transform = .identity
            outgoing.container.transform = CGAffineTransform(translationX: 0, y: down ? -h : h)
        } completion: { [weak self] _ in
            guard let self else { return }
            // 错峰：新槽已占屏，旧槽 pause，0.5s 后清（只清非相邻，相邻保留供回切）
            outgoing.player.pause()
            if abs(outgoing.index - index) > 1 {
                outgoing.pauseAndReleaseLater(delay: 0.5)
            }
            self.activeIdx = self.slots.firstIndex(where: { $0 === incoming }) ?? 0
            self.isAnimating = false
            // 预载下一条到腾出的槽
            self.preloadNext(around: index)
            DYLog.shared.log("DUAL slide done activeIdx=\(self.activeIdx) idx=\(index)")
        }
    }

    /// 预载下一条到备用槽（静音）。
    private func preloadNext(around index: Int) {
        let standby = standbySlot
        guard let next = itemURL(at: index + 1), standby.index != index + 1 else { return }
        standby.load(url: next, index: index + 1, muted: true, cover: nil, onReady: { [weak self] in
            guard let self else { return }
            DYLog.shared.log("DUAL preload ready idx=\(index + 1)")
        }, onFailed: { [weak self] in
            guard let self else { return }
            DYLog.shared.log("DUAL preload failed idx=\(index + 1)")
        })
    }

    // MARK: - 导航

    private func advance() {
        PlaybackEngine.shared.next()
        reloadIfNeeded()
    }
    private func rewind() {
        PlaybackEngine.shared.prev()
        reloadIfNeeded()
    }

    // MARK: - 遥控

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

    private func seek(by seconds: Double) {
        let p = activeSlot.player
        guard let t = p.currentItem?.currentTime().seconds, t.isFinite else { return }
        let target = max(0, t + seconds)
        p.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        DYLog.shared.log("DUAL seek \(seconds)s -> \(target)")
    }

    private func togglePlayPause() {
        let p = activeSlot.player
        if p.timeControlStatus == .playing { p.pause() } else { p.play() }
    }
}

/// SwiftUI 包装：双播放器池 + 真实双视频图层垂直滑动。
struct NativePlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DYPlayerViewController {
        DYPlayerViewController()
    }
    func updateUIViewController(_ uiViewController: DYPlayerViewController, context: Context) {}
}
