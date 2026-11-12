import UIKit
import AVKit
import SwiftUI
import Combine

/// 原生播放器（前景）：继承 AVPlayerViewController（tvOS 原生路径，Menu 键干净退出）。
/// 视频重力 = resizeAspect（居中、不裁切），letterbox 区透明露出容器背后的模糊背景。
/// 上/下遥控键覆盖为 prev/next；左/右仍走原生 seek。
/// 关键：监听 item 失败/播完自动跳下一条（解卡永久黑屏）；预加载前后各 2 条。
/// 焦点意图：播放器传输控件参与焦点；上/下被本类拦截改语义。
final class DYPlayerViewController: AVPlayerViewController {
    private var cancellables = Set<AnyCancellable>()
    private var currentIndex: Int = -1
    private var preloadCache: [Int: AVPlayerItem] = [:]
    private let preloadRadius = 2

    override func viewDidLoad() {
        super.viewDidLoad()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        // 前景：居中、不裁切（约束要求），letterbox 透明露出背后模糊背景
        videoGravity = .resizeAspect
        view.backgroundColor = .clear
        player = AVPlayer()
        DYLog.shared.log("PLAYER foreground viewDidLoad")

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

    private func item(at index: Int) -> AVPlayerItem? {
        guard PlaybackEngine.shared.urls.indices.contains(index) else { return nil }
        let url = PlaybackEngine.shared.urls[index]
        if let cached = preloadCache[index] { return cached }
        let item = AVPlayerItem(url: url)
        preloadCache[index] = item
        observeItem(item, index: index)
        return item
    }

    /// 监听 item 失败/播完 → 自动跳下一条（解"缓冲完仍黑屏不播"）。
    private func observeItem(_ item: AVPlayerItem, index: Int) {
        NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            DYLog.shared.log("PLAYER item ended index=\(index), auto-next")
            self?.advance()
        }
        item.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
        item.addObserver(self, forKeyPath: "error", options: [.new], context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let item = object as? AVPlayerItem else { return super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context) }
        if keyPath == "status", item.status == .failed {
            let idx = preloadCache.first(where: { $0.value == item })?.key ?? -1
            DYLog.shared.log("PLAYER item FAILED index=\(idx) err=\(item.error?.localizedDescription ?? "?"), skip")
            if item == player?.currentItem { advance() }
        }
    }

    private func reloadIfNeeded() {
        let engine = PlaybackEngine.shared
        guard engine.index != currentIndex else { return }
        currentIndex = engine.index
        guard let it = item(at: currentIndex) else {
            DYLog.shared.log("PLAYER no url at index=\(engine.index)")
            return
        }
        DYLog.shared.log("PLAYER play index=\(currentIndex) url=\((it.asset as? AVURLAsset)?.url.absoluteString.prefix(80) ?? "?")")
        player?.replaceCurrentItem(with: it)
        player?.play()
        preloadNeighbors(around: currentIndex)
    }

    private func preloadNeighbors(around index: Int) {
        for offset in -preloadRadius...preloadRadius where offset != 0 {
            let i = index + offset
            if PlaybackEngine.shared.urls.indices.contains(i) { _ = item(at: i) }
        }
    }

    private func advance() {
        PlaybackEngine.shared.next()
        reloadIfNeeded()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .downArrow:
                advance()
                return
            case .upArrow:
                PlaybackEngine.shared.prev()
                reloadIfNeeded()
                return
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }
}

/// 容器：背后一层"同一视频 aspectFill + 高斯模糊"填满 16:9，前景内嵌 AVPlayerViewController 居中清晰视频。
/// 两层共用同一个 AVPlayer（由 DYPlayerViewController 创建），天然同步。
final class DYPlayerContainerViewController: UIViewController {
    private let bgVideoLayer = AVPlayerLayer()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    private var playerVC: DYPlayerViewController!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        DYLog.shared.log("CONTAINER viewDidLoad")

        // 背景视频层：aspectFill 铺满，随后被 blur 覆盖成模糊背景（填满黑边区域）
        let bgView = UIView()
        bgVideoLayer.videoGravity = .resizeAspectFill
        bgView.layer.addSublayer(bgVideoLayer)
        bgView.frame = view.bounds
        bgView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(bgView)

        blurView.frame = view.bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(blurView)

        // 前景 AVPlayerViewController：居中清晰、不裁切、背景透明
        playerVC = DYPlayerViewController()
        addChild(playerVC)
        playerVC.view.frame = view.bounds
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(playerVC.view)
        playerVC.didMove(toParent: self)

        // 背景层绑定到前景同一个 AVPlayer（child 在 viewDidLoad 创建 player，此处取到）
        DispatchQueue.main.async { [weak self] in
            self?.bgVideoLayer.player = self?.playerVC.player
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        bgVideoLayer.frame = view.bounds
    }
}

/// SwiftUI 包装：全屏原生播放器（模糊背景 + 居中清晰竖版视频）。
struct NativePlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DYPlayerContainerViewController {
        DYPlayerContainerViewController()
    }
    func updateUIViewController(_ uiViewController: DYPlayerContainerViewController, context: Context) {}
}
