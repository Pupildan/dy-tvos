import SwiftUI
import AVKit
import AVFoundation

/// 顶层视图。纯原生闭环：DYFeedClient(移动端签名直连) → PlaybackEngine → AVPlayer。
/// 零 WebView：数据层由 myDV 移动端接口接管（JSContext 本地签名 + URLSession 直连），
/// 播放流程不出现任何 WebView。
/// v135 设置面板：屏幕左侧悬浮液态玻璃面板（Menu 第一次按呼出；显示中再按=退出应用）。
struct RootView: View {
    @State private var started = false
    @State private var showLaunchVideo = true   // v195：冷启动加载视频 overlay（首帧 ready 后淡出）
    @ObservedObject private var engine = PlaybackEngine.shared
    @ObservedObject private var settings = DYSettingsModel.shared
    @ObservedObject private var quick = DYQuickPanelModel.shared

    var body: some View {
        ZStack(alignment: .leading) {
            // 原生播放器全屏（居中、不裁切、周围留白——原始约束）
            NativePlayerView()
                .ignoresSafeArea()

            // 设置面板（左侧悬浮；Menu 呼出，显示中 Menu=退出应用）
            if settings.isOpen {
                SettingsPanelView()
                    .ignoresSafeArea()
                    .zIndex(10)
            }

            // 快捷悬浮窗（v145：OK 呼出，屏幕中下；Menu=关闭回播放）
            if quick.isOpen {
                DYQuickPanelView()
                    .ignoresSafeArea()
                    .zIndex(9)
            }

            // 评论屏（v147：快捷面板「评论」打开；Menu 关闭回播放）
            if quick.isCommentOpen {
                DYCommentScreen()
                    .ignoresSafeArea()
                    .zIndex(11)
            }

            // 作者主页屏（v153：快捷面板「主页」打开；Menu 关闭回播放）
            if quick.isProfileOpen {
                DYProfileScreen()
                    .ignoresSafeArea()
                    .zIndex(12)
            }

            // v172 合集屏（快捷面板「合集」打开；mix/aweme 页面上下文截获）
            if quick.isMixOpen {
                DYMixScreen()
                    .ignoresSafeArea()
                    .zIndex(12)
            }

            // v183 直播流屏（设置面板「直播」打开；全屏纵向分页刷直播间 + 无限加载，v184）
            if quick.isLiveOpen {
                DYLiveFeedScreen()
                    .ignoresSafeArea()
                    .zIndex(13)
            }

            // 轻提示（v150：主页/合集等占位动作反馈，2.5s 自动消失）
            if let toast = quick.toast {
                Text(toast)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.75))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 210)
                    .zIndex(20)
                    .transition(.opacity)
            }

            // v195 启动加载视频：冷启动遮住黑屏，静音循环；主 feed 首帧 ready 后交叉淡化到视频
            if showLaunchVideo {
                LaunchVideoOverlay()
                    .ignoresSafeArea()
                    .zIndex(30)
                    .transition(.opacity)
            }
        }
        .background(Color.black)
        .onAppear {
            guard !started else { return }
            started = true
            DanmakuOverlay.globalEnabled = settings.danmakuOn
            DYLog.shared.log("ROOT auto-start \(DYBuild.version)")
        }
        // v195：主 feed 首帧 ready → 交叉淡化掉启动加载视频（不突兀，露出底下 NativePlayerView）
        .onChange(of: engine.firstFrameReady) { ready in
            guard ready, showLaunchVideo else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                showLaunchVideo = false
            }
            DYLog.shared.log("ROOT launch video fade out (first frame ready)")
        }
        // v175：移除此处 v163 原型的重复 fetch（DYProfileScreen.onAppear 已发）；
        // 真机日志实锤双发 profcap/postcap 白等 2s，且双发的队列会互相踩分页游标。
        .onChange(of: quick.isProfileOpen) { open in
            guard open else { return }
            DYLog.shared.log("ROOT profile open → \(quick.profileSecUid.prefix(16))... (数据由 DYProfileScreen.onAppear 发起)")
        }
        // v186：进直播流屏暂停主 feed 所有 player（真机实锤两层声音叠加）；退出后 scrollTo 恢复居中播放
        .onChange(of: quick.isLiveOpen) { open in
            if open {
                PlayerManager.shared.pauseAll()
                DYLog.shared.log("ROOT live open → main feed paused")
            }
        }
    }
}

// MARK: - 启动加载视频（v195：冷启动遮住黑屏，静音循环，主 feed 首帧 ready 后交叉淡化）
// 照 myDV/AVPlayerViewController 出画面方案；视频打包在 App/Resources/loading.mp4（Bundle.main 访问，照 DYSigner 同款）。

struct LaunchVideoOverlay: View {
    var body: some View {
        LaunchVideoPlayerView()
            .background(Color.black)   // 视频未 render 前兜底黑底（不是纯黑闪，是视频首帧前的底色）
    }
}

struct LaunchVideoPlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspect
        // 打包的加载视频（App/Resources/loading.mp4 → Bundle.main 访问，照 DYSigner.swift:89 同款）
        guard let url = Bundle.main.url(forResource: "loading", withExtension: "mp4") else {
            DYLog.shared.log("LAUNCH loading.mp4 missing in bundle")
            return vc
        }
        let player = AVPlayer(url: url)
        player.isMuted = true          // 静音（需求：不能有声音）
        player.actionAtItemEnd = .none // 播完不暂停，配合循环
        vc.player = player
        player.play()
        // 循环：播完回到开头续播（静音加载动画循环遮住黑屏直到主 feed 首帧 ready）
        // ⚠️ object 传局部非可选 item（player.currentItem 可选会污染 .AVPlayerItemDidPlayToEnd 成员查找，v195 CI 实锤）
        if let item = player.currentItem {
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEnd, object: item, queue: .main) { [weak player] _ in
                player?.seek(to: .zero)
                player?.play()
            }
        }
        DYLog.shared.log("LAUNCH loading video play (muted loop)")
        return vc
    }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}

