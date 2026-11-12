import SwiftUI

/// 顶层视图。启动即自动：隐藏 WebView 当数据泵拉 feed，原生 AVPlayer 播放。
/// 焦点意图：原生播放器持有焦点；泵 WebView 非 focusable，不劫持遥控器。
/// 无测试按钮（探测逻辑保留在 WebKitProbe 但不在 UI 暴露）。
struct RootView: View {
    @State private var shellStatus: String = "启动中…"
    @State private var started = false

    var body: some View {
        ZStack {
            // 数据泵 WebView：全屏藏在原生播放器背后（不透明度极低但仍在层级里）。
            // 必须够大，抖音的懒加载/intersection 才会随自动滚动持续翻页拉新 feed。
            WebKitShellView(statusText: $shellStatus)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(0.02)
                .accessibilityHidden(true)
            // 原生播放器全屏覆盖（居中、不裁切、周围留白）
            NativePlayerView()
                .ignoresSafeArea()
        }
        .background(Color.black)
        .onAppear {
            guard !started else { return }
            started = true
            DYLog.shared.log("ROOT auto-start \(DYBuild.version)")
        }
    }
}
