import SwiftUI
import AVKit
import AVFoundation

/// 顶层视图。纯原生闭环：DYFeedClient(移动端签名直连) → PlaybackEngine → AVPlayer。
/// 零 WebView：数据层由 myDV 移动端接口接管（JSContext 本地签名 + URLSession 直连），
/// 播放流程不出现任何 WebView。
/// v135 设置面板：屏幕左侧悬浮液态玻璃面板（Menu 第一次按呼出；显示中再按=退出应用）。
struct RootView: View {
    @State private var started = false
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
        }
        .background(Color.black)
        .onAppear {
            guard !started else { return }
            started = true
            DanmakuOverlay.globalEnabled = settings.danmakuOn
            DYLog.shared.log("ROOT auto-start \(DYBuild.version)")
        }
    }
}
