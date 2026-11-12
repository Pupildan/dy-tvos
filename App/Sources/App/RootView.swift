import SwiftUI

/// 顶层视图。U-A0/U-A1：探针 A 路线（私有 WebKit）+ 打开抖音网页（扫码登录）。
/// 焦点意图：两个 Button 可聚焦，上下键在两按钮间移动；状态/结果区是纯 Text 不可聚焦，不会劫持焦点。
struct RootView: View {
    @State private var probeResult: String = "点「运行探针」检测 A 路线可行性"
    @State private var shellStatus: String = ""
    @State private var showShell = false

    var body: some View {
        VStack(spacing: 24) {
            Text("DYTV — WebKit 探针")
                .font(.system(size: 44, weight: .bold))

            Button("运行探针") {
                probeResult = WebKitProbe.run().summary
            }
            .font(.title3)

            Button("打开抖音网页（扫码登录）") {
                showShell = true
            }
            .font(.title3)

            if showShell {
                // 原生播放：WebView 隐藏当数据泵（必须在视图层级里 JS 才跑、才翻页拉 feed），
                // 原生 AVPlayerViewController 全屏覆盖，实现"看不到网页、纯原生"。
                ZStack {
                    // 数据泵 WebView：藏到底层，缩小 + 近乎全透明，但仍在层级里跑 JS
                    WebKitShellView(statusText: $shellStatus)
                        .frame(width: 320, height: 180)
                        .opacity(0.02)
                        .accessibilityHidden(true)
                    // 原生播放器（上/下键切视频，左/右 seek，Menu 干净退出）
                    NativePlayerView()
                        .ignoresSafeArea()
                }
                // 焦点意图：原生播放器持有焦点；泵 WebView 非 focusable，不劫持遥控器
            } else {
                Text(probeResult)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.quaternary)
                    .cornerRadius(12)
            }

            Text(DYBuild.version)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
