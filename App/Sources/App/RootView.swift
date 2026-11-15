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
        }
        .background(Color.black)
        .onAppear {
            guard !started else { return }
            started = true
            DanmakuOverlay.globalEnabled = settings.danmakuOn
            DYLog.shared.log("ROOT auto-start \(DYBuild.version)")
        }
        // v163 作品列表 WebView 截获原型：作者主页一打开，离屏 WebView 加载作者页、
        // 截获页面自己发出的 aweme/post 响应（真 168 签名）→ 全量日志。
        // 原型验证用，独立于 DYProfileClient 数据流，零 UI 改动。
        .onChange(of: quick.isProfileOpen) { open in
            guard open else { return }
            let sec = quick.profileSecUid
            guard !sec.isEmpty else { return }
            DYLog.shared.log("ROOT profile open → WORKSCAP secUid=\(sec.prefix(16))...")
            DYWorksCapture.shared.fetch(secUid: sec)
        }
    }
}
