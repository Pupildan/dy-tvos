import UIKit
import AVKit
import AVFoundation
import SwiftUI

/// 启动加载动画：全屏循环静音播放 bundle 里的 launch_video.mp4，
/// 替代文字 Loading。feed 首批就绪后由 RootView 淡出移除。
struct LaunchVideoView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> LaunchVideoViewController {
        LaunchVideoViewController()
    }
    func updateUIViewController(_ uiViewController: LaunchVideoViewController, context: Context) {}
}

final class LaunchVideoViewController: UIViewController {
    private let player = AVPlayer()
    private var endObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let url = Bundle.main.url(forResource: "launch_video", withExtension: "mp4") else {
            DYLog.shared.log("LAUNCH video missing in bundle")
            return
        }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.isMuted = true                      // 静音（不抢真实视频声音）
        player.actionAtItemEnd = .none
        // 循环播放
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }
        player.play()
        DYLog.shared.log("LAUNCH video play (loop, muted)")
    }

    deinit {
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        player.pause()
    }
}
