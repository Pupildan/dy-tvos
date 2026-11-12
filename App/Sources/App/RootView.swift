import SwiftUI

/// 顶层视图。启动即自动：全屏隐藏 WebView 当数据泵（自己滚动触发抖音翻页+签名），
/// fetch hook 拦截 feed JSON 抽直链喂给原生 AVPlayer；首批一到自动播 index 0。
/// 加载态：直链未到时显示原生 Loading 动画。
/// 焦点意图：原生播放器持有焦点；泵 WebView 非 focusable，不劫持遥控器。
struct RootView: View {
    @State private var started = false
    @ObservedObject private var engine = PlaybackEngine.shared

    var body: some View {
        ZStack {
            // 数据泵 WebView：全屏藏在原生播放器背后。够大，滚动/懒加载才会持续翻页。
            // 不透明度极低（用户看不到），但仍在层级里跑 JS、响应滚动、发 feed 请求。
            WebKitShellView(statusText: .constant(""))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.02)
                .accessibilityHidden(true)

            // 原生播放器全屏覆盖（居中、不裁切、周围留白）
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
