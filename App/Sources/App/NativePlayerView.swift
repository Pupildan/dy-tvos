import UIKit
import AVKit
import AVFoundation
import SwiftUI
import Combine

/// 双播放器池槽位：容器 UIView + 内嵌 AVPlayerLayer + AVPlayer。
/// 关键：动画作用于 container（UIView），UIKit 对 view 动画可靠；
/// 直接动画 AVPlayerLayer（挂在 view.layer 上）在真机不产生动画（瞬移）。
/// 内存纪律：后台预载只缓冲 3 秒、强制静音；滑出屏外的旧槽 clear() 释放资源。
final class DYPlayerSlot {
    let player: AVPlayer
    let container: UIView          // 动画作用于此 view 的 transform
    private let layer: AVPlayerLayer
    private(set) var index: Int = -1
    /// 正在加载的目标 index（加载中非 nil）——防止滑动完成回调误清正在装载的槽
    var loadingIndex: Int? = nil
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    var currentItem: AVPlayerItem? { player.currentItem }

    init() {
        player = AVPlayer()
        container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        layer = AVPlayerLayer()
        layer.player = player
        layer.videoGravity = .resizeAspect   // 居中、不裁切、周围留白（原始约束）
        layer.backgroundColor = UIColor.black.cgColor
        container.layer.addSublayer(layer)
    }

    /// container 布局（由 VC 在 layoutSubviews 调用）
    func layout(in bounds: CGRect) {
        container.frame = bounds
        layer.frame = container.bounds
    }

    /// 绑定 item + 状态/播完监听。后台预载：静音 + 只缓冲 3 秒。
    func load(url: URL, index: Int, muted: Bool, onReady: @escaping () -> Void, onFailed: @escaping () -> Void) {
        self.index = index
        removeAllObservers()
        let headers: [String: String] = {
            var h = ["User-Agent": DYFeedClient.mobileUA]
            if let cookie = DYFeedClient.shared.cookieHeaderForPlayback(), !cookie.isEmpty {
                h["Cookie"] = cookie
            }
            return h
        }()
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 3.0   // 只缓冲起步 3 秒，省内存/流量
        asset.loadValuesAsynchronously(forKeys: ["playable"])
        player.replaceCurrentItem(with: item)
        player.isMuted = muted                       // 后台预载强制静音

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
            onFailed()   // 播完 → 走 advance（复用失败跳转路径）
        }
    }

    /// 清空槽位资源：replaceCurrentItem(with:nil) 释放解码器/缓冲，防内存溢出。
    func clear() {
        removeAllObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
        index = -1
        loadingIndex = nil
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

/// 原生播放器：双播放器池 + 垂直滑动过渡（模拟抖音上下滑）。
/// PlayerA/PlayerB 各一个容器 UIView（内嵌 AVPlayerLayer）叠满全屏，永远只显示一个；
/// 切换时新旧容器做物理位移动画（UIView.animate curveEaseInOut 0.3s），彻底消灭黑屏/瞬移。
/// 遥控：上=prev(从上滑入) 下=next(从下滑入) 左右=seek Menu=退出。
final class DYPlayerViewController: UIViewController {
    private var cancellables = Set<AnyCancellable>()
    private let slotA = DYPlayerSlot()
    private let slotB = DYPlayerSlot()
    private lazy var slots: [DYPlayerSlot] = [slotA, slotB]
    /// 当前前台可见的槽（0=A, 1=B）
    private var activeIdx = 0
    private var currentIndex: Int = -1
    private var isAnimating = false
    private let animDuration: TimeInterval = 0.3

    private var activeSlot: DYPlayerSlot { slots[activeIdx] }
    private var standbySlot: DYPlayerSlot { slots[1 - activeIdx] }
    private var screenHeight: CGFloat { view.bounds.height }

    override func viewDidLoad() {
        super.viewDidLoad()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        view.backgroundColor = .black
        DYLog.shared.log("DUALPLAYER viewDidLoad")

        // 容器 view 叠满全屏（动画作用于 container 的 transform）
        for s in slots {
            s.container.frame = view.bounds
            view.addSubview(s.container)
        }
        // A 在前台，B 预置到屏幕下方（隐藏在底）
        slotA.container.transform = .identity
        slotB.container.transform = CGAffineTransform(translationX: 0, y: screenHeight)

        PlaybackEngine.shared.$index
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadIfNeeded() }
            .store(in: &cancellables)
        PlaybackEngine.shared.$urls
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadIfNeeded() }
            .store(in: &cancellables)

        reloadIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for s in slots { s.layout(in: view.bounds) }
    }

    // MARK: - 装载/预加载

    private func itemURL(at index: Int) -> URL? {
        guard PlaybackEngine.shared.urls.indices.contains(index) else { return nil }
        return PlaybackEngine.shared.urls[index]
    }

    /// 装载槽位。前台槽出声，后台预载槽静音。
    /// 关键：静音只在【该槽当前确是备用槽】时生效；若它已滑到前台（正在播），绝不静音/重载。
    private func load(slot: DYPlayerSlot, index: Int, muted: Bool) {
        // 已是目标内容：只在它是备用槽时才静音，前台槽保持出声，且不重载
        if slot.index == index, slot.currentItem != nil {
            let isStandby = (slot !== activeSlot)
            slot.player.isMuted = muted && isStandby
            return
        }
        guard let url = itemURL(at: index) else { return }
        slot.loadingIndex = index   // 标记加载中，防止滑动完成回调误清
        slot.load(url: url, index: index, muted: muted, onReady: { [weak self] in
            guard let self else { return }
            slot.loadingIndex = nil
            // ready 时再校验：若已滑到前台则保持出声
            let isStandby = (slot !== self.activeSlot)
            slot.player.isMuted = muted && isStandby
            DYLog.shared.log("DUAL slot ready idx=\(index) keepMuted=\(isStandby)")
        }, onFailed: { [weak self] in
            guard let self else { return }
            slot.loadingIndex = nil
            DYLog.shared.log("DUAL idx=\(index) failed/ended (isActive=\(self.activeSlot === slot))")
            if self.activeSlot === slot {
                PlaybackEngine.shared.reportFailure()
                self.advance()
            }
        })
    }

    private func reloadIfNeeded() {
        let engine = PlaybackEngine.shared
        guard engine.index != currentIndex else { return }
        guard itemURL(at: engine.index) != nil else {
            // 取不到 URL 不提交 index，等 setURLs 后重试播 index 0
            DYLog.shared.log("DUAL no url at index=\(engine.index) (will retry)")
            return
        }
        let previousIndex = currentIndex
        currentIndex = engine.index

        // 首次：直接装到 active 槽播放（无滑动，前台出声）
        if previousIndex == -1 {
            load(slot: activeSlot, index: engine.index, muted: false)
            activeSlot.player.play()
            preloadNext(around: engine.index)
            DYLog.shared.log("DUAL first play idx=\(engine.index)")
            return
        }

        // 后续：备用槽应已预载 engine.index（上次 preloadNext）。若没装，现装（静音）。
        let standby = standbySlot
        if standby.index != engine.index {
            load(slot: standby, index: engine.index, muted: true)
        }
        slideTransition(to: standby, index: engine.index, direction: engine.index > previousIndex ? .down : .up)
        preloadNext(around: engine.index)
    }

    /// 预加载下一条到备用槽（静音、只缓冲 3 秒）。
    private func preloadNext(around index: Int) {
        let standby = standbySlot
        if let next = itemURL(at: index + 1), standby.index != index + 1 {
            load(slot: standby, index: index + 1, muted: true)
        }
    }

    // MARK: - 垂直滑动过渡（动画容器 view 的 transform）

    private enum SlideDir { case down, up }

    /// 把 standby（已装载 index）滑入前台，active 滑出；down=下滑入(下一个) up=上滑入(上一个)。
    private func slideTransition(to incoming: DYPlayerSlot, index: Int, direction: SlideDir) {
        guard !isAnimating else { return }
        isAnimating = true
        let outgoing = activeSlot
        // 关键：确保容器 frame 就绪（否则 transform 动画作用在零 frame 上 → 视觉无效/瞬移）
        view.layoutIfNeeded()
        let h = screenHeight

        // 入场起点：下一个从下方来，上一个从上方来（容器 view transform）
        incoming.container.transform = CGAffineTransform(translationX: 0, y: direction == .down ? h : -h)
        view.bringSubviewToFront(incoming.container)

        // 滑到前台 → 取消静音出声
        incoming.player.isMuted = false
        incoming.player.play()

        DYLog.shared.log("DUAL slide \(direction == .down ? "next" : "prev") -> idx=\(index)")
        UIView.animate(withDuration: animDuration, delay: 0, options: [.curveEaseInOut]) { [weak self] in
            guard let self else { return }
            // 入场滑到中央
            incoming.container.transform = .identity
            // 出场滑向对侧（下一个→往上出；上一个→往下出）
            let outY: CGFloat = direction == .down ? -h : h
            outgoing.container.transform = CGAffineTransform(translationX: 0, y: outY)
        } completion: { [weak self] _ in
            guard let self else { return }
            // 收尾：旧槽暂停、复位到屏幕下方待命
            outgoing.player.pause()
            outgoing.container.transform = CGAffineTransform(translationX: 0, y: self.screenHeight)

            self.activeIdx = self.slots.firstIndex(where: { $0 === incoming }) ?? 0
            self.isAnimating = false

            // 内存纪律：只清【非相邻 + 没在加载】的槽，绝不清正在用/正在装载的（防 Cannot Open 黑帧）
            if self.isKeepWorthy(outgoing) {
                outgoing.clear()
            }
            // 立即预载下一条到刚腾出的备用槽
            self.preloadNext(around: self.currentIndex)
            DYLog.shared.log("DUAL slide done activeIdx=\(self.activeIdx) idx=\(index)")
        }
    }

    /// 槽是否可安全清空：非相邻（|index-current|>1）且没在加载下一条。
    private func isKeepWorthy(_ slot: DYPlayerSlot) -> Bool {
        if let li = slot.loadingIndex, abs(li - currentIndex) <= 1 { return false }   // 正在加载相邻内容
        if slot.index != -1, abs(slot.index - currentIndex) <= 1 { return false }      // 相邻保留（供回切）
        return true
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

    // MARK: - 遥控（双 player 自管，需自行接键）

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .downArrow:
                advance()
                return
            case .upArrow:
                rewind()
                return
            case .leftArrow, .rightArrow:
                seek(by: press.type == .rightArrow ? 10 : -10)
                return
            case .playPause:
                togglePlayPause()
                return
            default:
                break
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

/// SwiftUI 包装：双播放器池全屏原生播放器（垂直滑动切换）。
struct NativePlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DYPlayerViewController {
        DYPlayerViewController()
    }
    func updateUIViewController(_ uiViewController: DYPlayerViewController, context: Context) {}
}
