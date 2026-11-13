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

    /// 无缝切换遮罩：换源瞬间盖黑，新源 readyToPlay 后 0.2s 淡出（消灭黑屏转圈）。
    private let switchCover: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.alpha = 0
        v.isUserInteractionEnabled = false   // 绝不抢遥控器焦点
        return v
    }()
    private var isSwitching = false

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

        // 无缝切换遮罩：盖在最上层（AVPlayerViewController 的视频层之上）
        view.addSubview(switchCover)
        switchCover.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            switchCover.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            switchCover.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            switchCover.topAnchor.constraint(equalTo: view.topAnchor),
            switchCover.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        view.bringSubviewToFront(switchCover)
    }

    private func item(at index: Int) -> AVPlayerItem? {
        guard PlaybackEngine.shared.urls.indices.contains(index) else { return nil }
        let url = PlaybackEngine.shared.urls[index]
        if let cached = preloadCache[index] { return cached }
        // 关键：CDN 直链需移动端请求上下文（UA/Cookie），否则 403 no-permission。
        // UA 用移动端 UA（与 feed 拉取一致，myDV 移动端直链配安卓 UA）。
        var headers: [String: String] = [
            "User-Agent": DYFeedClient.mobileUA,
        ]
        if let cookie = DYFeedClient.shared.cookieHeaderForPlayback(), !cookie.isEmpty {
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
        if keyPath == "status" {
            if item.status == .readyToPlay, item == player?.currentItem {
                // 新源首帧可播 → 淡出切换遮罩
                fadeOutCover()
            }
            if item.status == .failed {
                let idx = preloadCache.first(where: { $0.value == item })?.key ?? -1
                DYLog.shared.log("PLAYER item FAILED index=\(idx) err=\(item.error?.localizedDescription ?? "?")")
                PlaybackEngine.shared.reportFailure() // 连续失败/过期 → 触发页面重拉新直链
                if item == player?.currentItem { advance() }
            }
        }
    }

    private func reloadIfNeeded() {
        let engine = PlaybackEngine.shared
        guard engine.index != currentIndex else { return }
        guard let it = item(at: engine.index) else {
            // 关键：取不到 item 时【不提交】currentIndex，等 setURLs 到达后自动重试播 index 0。
            // （否则 currentIndex 提前=0，之后 0!=0 恒假，首条永远播不出 → 只能手动切。）
            DYLog.shared.log("PLAYER no url at index=\(engine.index) (will retry)")
            return
        }
        currentIndex = engine.index
        DYLog.shared.log("PLAYER play index=\(currentIndex) url=\((it.asset as? AVURLAsset)?.url.absoluteString.prefix(80) ?? "?")")
        // 换源瞬间盖黑（无缝切换），等新源 readyToPlay 后淡出
        isSwitching = true
        view.bringSubviewToFront(switchCover)
        switchCover.alpha = 1
        player?.replaceCurrentItem(with: it)
        player?.play()
        preloadNeighbors(around: currentIndex)
        // 兜底：若 item 已 ready（预加载命中），立即淡出
        if it.status == .readyToPlay { fadeOutCover() }
    }

    /// 新源首帧可播 → 0.2s 淡出遮罩。
    private func fadeOutCover() {
        guard isSwitching else { return }
        isSwitching = false
        UIView.animate(withDuration: 0.2, animations: { [weak self] in
            self?.switchCover.alpha = 0
        })
    }

    private func preloadNeighbors(around index: Int) {
        for offset in -preloadRadius...preloadRadius where offset != 0 {
            let i = index + offset
            if PlaybackEngine.shared.urls.indices.contains(i), let it = item(at: i) {
                // 关键：让邻居 item 在后台真正缓冲（否则切过去才缓冲→黑屏 1-2s）。
                // 正向多缓冲（下一个），反向少缓冲（上一个）。
                it.preferredForwardBufferDuration = offset > 0 ? 8 : 2
                if let asset = it.asset as? AVURLAsset {
                    asset.loadValuesAsynchronously(forKeys: ["playable"])   // 后台预解析可播性
                }
            }
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
