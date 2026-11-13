import SwiftUI
import AVKit
import AVFoundation

/// 顶层视图。纯原生闭环：DYFeedClient(移动端签名直连) → PlaybackEngine → AVPlayer。
/// 零 WebView：数据层由 myDV 移动端接口接管（JSContext 本地签名 + URLSession 直连），
/// 播放流程不出现任何 WebView。
/// 启动加载动画：首批直链未到时全屏循环静音播放 launch_video.mp4（替代文字 Loading），
/// feed 一到即淡出并自动播 index 0。
/// 焦点意图：原生播放器持有焦点（上/下切视频，左/右 seek，Menu 干净退出）。
struct RootView: View {
    @State private var started = false
    @State private var launchAlpha: Double = 1
    @ObservedObject private var engine = PlaybackEngine.shared

    var body: some View {
        ZStack {
            // 原生播放器全屏（居中、不裁切、周围留白——原始约束）
            NativePlayerView()
                .ignoresSafeArea()

            // 启动加载动画：全屏循环静音视频，feed 首批就绪后淡出
            if engine.urls.isEmpty {
                LaunchVideoView()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .background(Color.black)
        .onAppear {
            guard !started else { return }
            started = true
            DYLog.shared.log("ROOT auto-start \(DYBuild.version)")
        }
        // feed 首批就绪 → 淡出启动视频
        .onChange(of: engine.urls.isEmpty) { empty in
            guard !empty else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                launchAlpha = 0
            }
        }
    }
}
