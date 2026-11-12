import UIKit
import AVKit
import SwiftUI
import Combine

/// 原生播放器：继承 AVPlayerViewController（tvOS 原生路径，Menu 键干净退出）。
/// 上/下遥控键覆盖为 prev/next 视频；左/右仍交给 AVPlayerViewController 原生 seek。
/// 关键：监听 AVPlayerItem 错误/结束，失败或播完自动跳下一条（避免卡永久黑屏）。
/// 焦点意图：播放器自带传输控件参与焦点；上/下被本类拦截改语义，不落到其它视图。
final class DYPlayerViewController: AVPlayerViewController {
    private var cancellables = Set<AnyCancellable>()
    private var currentIndex: Int = -1
    private var itemObserver: NSObjectProtocol?
    private var timeObserver: Any?
    // 预加载缓存：index -> AVPlayerItem（提前建好，切换即播，减少黑屏）
    private var preloadCache: [Int: AVPlayerItem] = [:]
    private let preloadRadius = 2

    override func viewDidLoad() {
        super.viewDidLoad()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        // 铺满全屏：竖版视频裁上下填满 16:9（避免窄竖条）。要保比例改 .resizeAspect。
        videoGravity = .resizeAspectFill
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
    }

    /// 取或建某 index 的 AVPlayerItem（带预加载复用）。
    private func item(at index: Int) -> AVPlayerItem? {
        guard let url = PlaybackEngine.shared.urls.indices.contains(index) ? PlaybackEngine.shared.urls[index] : nil else { return nil }
        if let cached = preloadCache[index] { return cached }
        let item = AVPlayerItem(url: url)
        preloadCache[index] = item
        observeItem(item, index: index)
        return item
    }

    /// 监听单个 item 的失败/播完 → 自动跳下一条（解"缓冲完仍黑屏不播"）。
    private func observeItem(_ item: AVPlayerItem, index: Int) {
        NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTime, object: item, queue: .main) { [weak self] _ in
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

    /// 播引擎当前 index，并预加载前后各 preloadRadius 条。
    private func reloadIfNeeded() {
        let engine = PlaybackEngine.shared
        guard engine.index != currentIndex else { return }
        currentIndex = engine.index
        guard let it = item(at: currentIndex) else {
            DYLog.shared.log("PLAYER no url at index=\(engine.index)")
            return
        }
        DYLog.shared.log("PLAYER play index=\(currentIndex) url=\(it.url?.absoluteString.prefix(80) ?? "?")")
        player?.replaceCurrentItem(with: it)
        player?.play()
        preloadNeighbors(around: currentIndex)
    }

    /// 预加载当前 index 前后各 preloadRadius 条 item，保证切换流畅。
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

    // 上/下键 → prev/next 视频（覆盖 AVPlayerViewController 默认 seek 语义）
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

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let t = timeObserver { player?.removeTimeObserver(t); timeObserver = nil }
    }
}

/// SwiftUI 包装：全屏原生播放器。
struct NativePlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DYPlayerViewController {
        DYPlayerViewController()
    }
    func updateUIViewController(_ uiViewController: DYPlayerViewController, context: Context) {}
}
