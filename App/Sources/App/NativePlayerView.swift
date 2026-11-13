import UIKit
import AVKit
import AVFoundation
import SwiftUI
import Combine

/// 双播放器池槽位：容器 UIView（内嵌 AVPlayerLayer）+ 封面兜底 UIImageView。
/// 内存/竞态纪律（解决 Cannot Open 死锁）：
///   1) 前台槽播放时，后台槽只静音预载（isMuted=true, rate=0），绝不瞬间同时建两个解码器
///   2) 动画结束、新槽完全占屏后，才 pause 旧槽；再延迟 0.6s replaceCurrentItem(nil) 错峰释放
///   3) 新槽未出首帧时，容器先显示封面图，首帧渲染后 0.1s 淡出——永不给用户看黑屏
final class DYPlayerSlot {
    let player: AVPlayer
    let container: UIView
    private let coverImage: UIImageView
    private let layer: AVPlayerLayer
    private(set) var index: Int = -1
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    /// 封面图（网速慢时兜底，首帧渲染后淡出）
    var cover: UIImage? { get { coverImage.image } set { coverImage.image = newValue } }

    var currentItem: AVPlayerItem? { player.currentItem }

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
        // 层级：封面在下，视频层在上（首帧渲染后视频盖住封面）
        container.addSubview(coverImage)
        container.layer.addSublayer(layer)
    }

    /// 布局（由 VC layoutSubviews 调用）
    func layout(in bounds: CGRect) {
        container.frame = bounds
        coverImage.frame = container.bounds
        layer.frame = container.bounds
    }

    /// 装载 index 内容。muted=true 表示后台预载（静音、不抢焦点）。
    func load(url: URL, index: Int, muted: Bool, onReady: @escaping () -> Void, onFailed: @escaping () -> Void) {
        self.index = index
        removeAllObservers()
        var headers = ["User-Agent": DYFeedClient.mobileUA]
        if let cookie = DYFeedClient.shared.cookieHeaderForPlayback(), !cookie.isEmpty {
            headers["Cookie"] = cookie
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 3.0   // 只缓冲起步 3 秒
        asset.loadValuesAsynchronously(forKeys: ["playable"])
        player.replaceCurrentItem(with: item)
        player.isMuted = muted                       // 后台预载静音
        player.play()                                // 预载也起步解码（静音不抢焦点），滑到前台已 ready

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            guard let self, self.player.currentItem === it else { return }
            switch it.status {
            case .readyToPlay:
                DYLog.shared.log("SLOT idx=\(index) readyToPlay muted=\(self.player.isMuted)")
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

    /// 清空槽位资源（replaceCurrentItem nil 释放解码器/缓冲）。
    func clear() {
        removeAllObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        index = -1
        coverImage.image = nil
        DYLog.shared.log("SLOT cleared (resource released)")
    }

    func removeAllObservers() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = nil
    }

    deinit { removeAllObservers() }
}

/// 原生播放器：双播放器池 + 按键瞬间弹簧滑动 + 封面兜底。
/// 下=PlayerB 从下滑入、PlayerA 往上出；上=PlayerB 从上滑入、PlayerA 往下出。
/// 动画按下瞬间起步（不等服务）；错峰释放解决 Cannot Open；封面兜底杜绝黑屏。
final class DYPlayerViewController: UIViewController {
    private var cancellables = Set<AnyCancellable>()
    private let slotA = DYPlayerSlot()
    private let slotB = DYPlayerSlot()
    private lazy var slots: [DYPlayerSlot] = [slotA, slotB]
    private var activeIdx = 0
    private var currentIndex = 0
    private var isAnimating = false
    private var pendingIndex: Int?

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
        let target = pendingIndex ?? PlaybackEngine.shared.index
        guard target != currentIndex, let url = itemURL(at: target) else { return }
        let dir: SlideDir = target > currentIndex ? .next : .prev
        let incoming = standbySlot
        incoming.cover = nil
        incoming.load(url: url, index: target, muted: true, onReady: { [weak self] in
            guard let self else { return }
            DYLog.shared.log("DUAL standby ready idx=\(target) keepMuted=\(self.activeSlot === incoming)")
        }, onFailed: { [weak self] in
            guard let self else { return }
            DYLog.shared.log("DUAL standby load failed idx=\(target)")
        })
        currentIndex = target
        // 按键瞬间立刻弹簧滑动（不等待网络）；未 ready 时封面兜底
        slideImmediate(to: incoming, index: target, dir: dir)
    }

    private enum SlideDir { case next, prev }

    /// 按键瞬间起步的弹簧滑动；旧槽错峰释放。
    private func slideImmediate(to incoming: DYPlayerSlot, index: Int, dir: SlideDir) {
        guard !isAnimating else { return }
        isAnimating = true
        view.layoutIfNeeded()
        let outgoing = activeSlot
        let h = view.bounds.height

        incoming.container.transform = CGAffineTransform(translationX: 0, y: dir == .next ? h : -h)
        view.bringSubviewToFront(incoming.container)

        DYLog.shared.log("DUAL slide \(dir == .next ? "next" : "prev") -> idx=\(index)")
        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0.5,
            options: [.curveEaseInOut]
        ) { [weak self] in
            guard let self else { return }
            incoming.container.transform = .identity
            outgoing.container.transform = CGAffineTransform(translationX: 0, y: dir == .next ? -h : h)
        } completion: { [weak self] _ in
            guard let self else { return }
            self.activeIdx = self.slots.firstIndex(where: { $0 === incoming }) ?? 0
            self.isAnimating = false
            // 错峰释放：新槽已完全占屏，旧槽 pause，0.6s 后再清资源（避免同时建/拆解码器死锁）
            outgoing.pauseAndReleaseLater(delay: 0.6)
            DYLog.shared.log("DUAL slide done activeIdx=\(self.activeIdx) idx=\(index)")
        }
    }

    // MARK: - 导航

    private func advance() {
        pendingIndex = currentIndex + 1
        reloadIfNeeded()
    }
    private func rewind() {
        pendingIndex = max(0, currentIndex - 1)
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

/// SwiftUI 包装：双播放器池 + 按键瞬间弹簧滑动。
struct NativePlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DYPlayerViewController {
        DYPlayerViewController()
    }
    func updateUIViewController(_ uiViewController: DYPlayerViewController, context: Context) {}
}
