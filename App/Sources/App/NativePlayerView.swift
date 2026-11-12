import UIKit
import AVKit
import SwiftUI
import Combine

/// 原生播放器：继承 AVPlayerViewController（tvOS 原生路径，Menu 键干净退出）。
/// 视频重力 = resizeAspect（居中、不裁切、周围留白——满足原始约束，不拉伸全屏）。
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
        // 居中、不裁切、周围留白（原始约束：不拉伸全屏、不锁比例）
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
    }

    private func item(at index: Int) -> AVPlayerItem? {
        guard PlaybackEngine.shared.urls.indices.contains(index) else { return nil }
        let url = PlaybackEngine.shared.urls[index]
        if let cached = preloadCache[index] { return cached }
        // 关键：CDN 直链需浏览器请求头（Referer/Cookie/UA），否则 403 no-permission。
        // 模拟 WebView 的 <video> 请求上下文。
        var headers: [String: String] = [
            "Referer": "https://www.douyin.com/",
            "User-Agent": WebKitShellViewController.desktopUA,
        ]
        if let cookie = DYGetPageCookie(), !cookie.isEmpty {
            headers["Cookie"] = cookie
        }
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": headers,
        ])
        let item = AVPlayerItem(asset: asset)
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
            DYLog.shared.log("PLAYER item FAILED index=\(idx) err=\(item.error?.localizedDescription ?? "?")")
            PlaybackEngine.shared.reportFailure() // 连续失败/过期 → 触发页面重拉新直链
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

/// SwiftUI 包装：全屏原生播放器（居中、不裁切、周围留白）。
struct NativePlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DYPlayerViewController {
        DYPlayerViewController()
    }
    func updateUIViewController(_ uiViewController: DYPlayerViewController, context: Context) {}
}
