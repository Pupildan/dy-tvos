import UIKit
import AVKit
import SwiftUI
import Combine

/// 原生播放器：继承 AVPlayerViewController（tvOS 原生路径，Menu 键干净退出）。
/// 上/下遥控键覆盖为 prev/next 视频；左/右仍交给 AVPlayerViewController 原生 seek。
/// 焦点意图：播放器自带传输控件参与焦点；上/下被本类拦截改语义，不落到其它视图。
final class DYPlayerViewController: AVPlayerViewController {
    private var cancellables = Set<AnyCancellable>()
    private var currentIndex: Int = -1

    override func viewDidLoad() {
        super.viewDidLoad()
        // 音频会话：tvOS 媒体播放标准配置
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        DYLog.shared.log("PLAYER viewDidLoad")

        // 监听引擎 index 变化 → 换源播放
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

    /// 用引擎当前 URL 重建 AVPlayerItem（index 变或首载时）。
    private func reloadIfNeeded() {
        let engine = PlaybackEngine.shared
        guard engine.index != currentIndex else { return }
        currentIndex = engine.index
        guard let url = engine.currentURL else {
            DYLog.shared.log("PLAYER no url at index=\(engine.index)")
            return
        }
        DYLog.shared.log("PLAYER play index=\(engine.index) url=\(url.absoluteString.prefix(90))")
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.play()
    }

    // 上/下键 → prev/next 视频（覆盖 AVPlayerViewController 默认的 seek 语义）
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            switch press.type {
            case .downArrow:
                PlaybackEngine.shared.next()
                reloadIfNeeded()
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

/// SwiftUI 包装：全屏原生播放器。
struct NativePlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DYPlayerViewController {
        DYPlayerViewController()
    }
    func updateUIViewController(_ uiViewController: DYPlayerViewController, context: Context) {}
}
