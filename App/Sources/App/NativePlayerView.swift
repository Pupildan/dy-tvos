import UIKit
import AVKit
import AVFoundation
import SwiftUI
import Combine

/// 原生播放器：单 AVPlayer + 末帧快照遮罩 + 快照方向滑动过渡。
/// 稳定底座（回退自脆弱的双播放器池）：只有一个活解码器，绝无黑屏/跳号/无声。
/// 切换方向感：换源前截当前末帧铺满遮罩，新源 readyToPlay 后把快照【向反方向滑出】，
/// 视觉=当前画面被推走、新画面就位（抖音式方向感），但只有单解码器，稳定可控。
/// 遥控：上=prev(快照往下滑出) 下=next(快照往上滑出) 左右=seek Menu=退出。
final class DYPlayerViewController: AVPlayerViewController {
    private var cancellables = Set<AnyCancellable>()
    private var currentIndex: Int = -1
    private var preloadCache: [Int: AVPlayerItem] = [:]
    private let preloadRadius = 2
    /// 切换方向：next=快照往上滑出，prev=快照往下滑出
    private enum SlideDir { case next, prev }
    private var pendingDir: SlideDir = .next

    /// 末帧快照遮罩：换源前截当前帧铺满，新源就位后向反方向滑出。
    private let snapCover: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.alpha = 0
        v.isUserInteractionEnabled = false   // 绝不抢遥控器焦点
        return v
    }()
    private let snapImage: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit     // 与播放器 resizeAspect 一致，快照不变形
        iv.clipsToBounds = true
        return iv
    }()
    /// 新源未 Ready 时的极小 Loading 圈（第四点兜底：绝不给用户看黑屏）
    private let snapLoading: UIActivityIndicatorView = {
        let a = UIActivityIndicatorView(style: .large)
        a.color = .white
        a.hidesWhenStopped = true
        a.translatesAutoresizingMaskIntoConstraints = false
        return a
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        videoGravity = .resizeAspect
        view.backgroundColor = .black
        player = AVPlayer()
        DYLog.shared.log("PLAYER viewDidLoad")

        PlaybackEngine.shared.$index
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadIfNeeded() }
            .store(in: &cancellables)
        PlaybackEngine.shared.$urls
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadIfNeeded() }
            .store(in: &cancellables)

        reloadIfNeeded()

        // 快照遮罩盖在最上层（视频层之上）
        view.addSubview(snapCover)
        snapCover.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            snapCover.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            snapCover.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            snapCover.topAnchor.constraint(equalTo: view.topAnchor),
            snapCover.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        snapCover.addSubview(snapImage)
        snapImage.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            snapImage.leadingAnchor.constraint(equalTo: snapCover.leadingAnchor),
            snapImage.trailingAnchor.constraint(equalTo: snapCover.trailingAnchor),
            snapImage.topAnchor.constraint(equalTo: snapCover.topAnchor),
            snapImage.bottomAnchor.constraint(equalTo: snapCover.bottomAnchor),
        ])
        // 新源未 Ready 时的极小 Loading 圈（居中）
        snapCover.addSubview(snapLoading)
        NSLayoutConstraint.activate([
            snapLoading.centerXAnchor.constraint(equalTo: snapCover.centerXAnchor),
            snapLoading.centerYAnchor.constraint(equalTo: snapCover.centerYAnchor),
        ])
        view.bringSubviewToFront(snapCover)
    }

    private func item(at index: Int) -> AVPlayerItem? {
        guard PlaybackEngine.shared.urls.indices.contains(index) else { return nil }
        let url = PlaybackEngine.shared.urls[index]
        if let cached = preloadCache[index] { return cached }
        // CDN 直链需移动端请求上下文（UA/Cookie），否则 403 no-permission
        var headers: [String: String] = ["User-Agent": DYFeedClient.mobileUA]
        if let cookie = DYFeedClient.shared.cookieHeaderForPlayback(), !cookie.isEmpty {
            headers["Cookie"] = cookie
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        preloadCache[index] = item
        observeItem(item, index: index)
        return item
    }

    private func observeItem(_ item: AVPlayerItem, index: Int) {
        NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            DYLog.shared.log("PLAYER item ended index=\(index), auto-next")
            self?.advance(dir: .next)
        }
        item.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
        item.addObserver(self, forKeyPath: "error", options: [.new], context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let item = object as? AVPlayerItem else { return super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context) }
        if keyPath == "status" {
            if item.status == .readyToPlay, item == player?.currentItem {
                // 新源首帧可播 → 快照向反方向滑出（方向感）
                slideOutCover()
            }
            if item.status == .failed {
                let idx = preloadCache.first(where: { $0.value == item })?.key ?? -1
                DYLog.shared.log("PLAYER item FAILED index=\(idx) err=\(item.error?.localizedDescription ?? "?")")
                PlaybackEngine.shared.reportFailure()
                if item == player?.currentItem { advance(dir: .next) }
            }
        }
    }

    private func reloadIfNeeded() {
        let engine = PlaybackEngine.shared
        guard engine.index != currentIndex else { return }
        guard let it = item(at: engine.index) else {
            // 取不到 item 不提交 currentIndex，等 setURLs 后重试播 index 0
            DYLog.shared.log("PLAYER no url at index=\(engine.index) (will retry)")
            return
        }
        // 换源前：截当前末帧铺满快照遮罩（画面冻结），挡住底层黑帧
        captureSnapshotOfCurrent()
        currentIndex = engine.index
        DYLog.shared.log("PLAYER play index=\(currentIndex) url=\((it.asset as? AVURLAsset)?.url.absoluteString.prefix(80) ?? "?")")
        view.bringSubviewToFront(snapCover)
        snapCover.alpha = 1
        player?.replaceCurrentItem(with: it)
        player?.play()
        preloadNeighbors(around: currentIndex)
        // 兜底：若 item 已 ready（预载命中），立即滑出快照
        if it.status == .readyToPlay { slideOutCover() }
    }

    /// 用 AVAssetImageGenerator 截当前视频当前帧铺满快照（必须在 replaceCurrentItem 之前调）。
    private func captureSnapshotOfCurrent() {
        guard let item = player?.currentItem,
              let asset = item.asset as? AVURLAsset else {
            snapImage.image = nil
            return
        }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1920, height: 1080)
        let time = player?.currentTime() ?? .zero
        gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { [weak self] _, cgImage, _, result, _ in
            guard result == .succeeded, let cg = cgImage else { return }
            DispatchQueue.main.async {
                if let self, self.snapCover.alpha > 0.01 {
                    self.snapImage.image = UIImage(cgImage: cg)
                }
            }
        }
    }

    /// 新源首帧可播 → 快照向切换反方向滑出（next 往上、prev 往下），露出底下新画面。
    private func slideOutCover() {
        let h = view.bounds.height
        let dy: CGFloat = (pendingDir == .next) ? -h : h
        // 先确保快照在最上、完全不透明
        view.bringSubviewToFront(snapCover)
        snapCover.alpha = 1
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) { [weak self] in
            self?.snapCover.transform = CGAffineTransform(translationX: 0, y: dy)
        } completion: { [weak self] _ in
            guard let self else { return }
            // 复位快照，等待下次切换
            self.snapCover.transform = .identity
            self.snapCover.alpha = 0
            self.snapImage.image = nil
        }
    }

    private func preloadNeighbors(around index: Int) {
        for offset in -preloadRadius...preloadRadius where offset != 0 {
            let i = index + offset
            if PlaybackEngine.shared.urls.indices.contains(i), let it = item(at: i) {
                it.preferredForwardBufferDuration = offset > 0 ? 8 : 2   // 正向多缓冲
                if let asset = it.asset as? AVURLAsset {
                    asset.loadValuesAsynchronously(forKeys: ["playable"])
                }
            }
        }
    }

    private func advance(dir: SlideDir) {
        pendingDir = dir
        PlaybackEngine.shared.next()
        reloadIfNeeded()
    }

    private func rewind() {
        pendingDir = .prev
        PlaybackEngine.shared.prev()
        reloadIfNeeded()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .downArrow:
                advance(dir: .next)
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
        guard let t = player?.currentTime().seconds, t.isFinite else { return }
        let target = max(0, t + seconds)
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        DYLog.shared.log("PLAYER seek \(seconds)s -> \(target)")
    }

    private func togglePlayPause() {
        guard let p = player else { return }
        if p.timeControlStatus == .playing { p.pause() } else { p.play() }
    }
}

/// SwiftUI 包装：全屏原生播放器（快照方向滑动切换）。
struct NativePlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DYPlayerViewController {
        DYPlayerViewController()
    }
    func updateUIViewController(_ uiViewController: DYPlayerViewController, context: Context) {}
}
