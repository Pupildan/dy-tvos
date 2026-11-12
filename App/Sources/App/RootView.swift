import SwiftUI

/// 顶层视图。纯原生闭环：DYFeedClient(签名直连) → PlaybackEngine → AVPlayer。
/// WebView 泵已退役（myDV 数据层方案接管：JSContext 本地签名 + URLSession 直连）。
/// 加载态：首批直链未到时显示原生 Loading 动画，一到即自动播 index 0。
/// 焦点意图：原生播放器持有焦点（上/下切视频，左/右 seek，Menu 干净退出）。
struct RootView: View {
    @State private var started = false
    @ObservedObject private var engine = PlaybackEngine.shared

    var body: some View {
        ZStack {
            // 临时探针泵：只为抓取抖音真实完整 feed 请求 URL（v45 一次性），下版移除
            WebKitShellView(statusText: .constant(""))
                .frame(width: 800, height: 450)
                .opacity(0.02)
                .accessibilityHidden(true)

            // 原生播放器全屏（居中、不裁切、周围留白——原始约束）
            NativePlayerView()
                .ignoresSafeArea()

            // 原生加载态：直链未到时显示，一到即消失并自动播 index 0
            if engine.urls.isEmpty {
                Color.black.ignoresSafeArea()
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.6)
                    Text("正在加载视频…")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black)
        .onAppear {
            guard !started else { return }
            started = true
            DYLog.shared.log("ROOT auto-start \(DYBuild.version)")
        }
    }
}
