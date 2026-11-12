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
                // WebView 必须在场才会加载抖音并触发 Feed API（JS 才跑）；缩小置底，不抢视觉
                WebKitShellView(statusText: $shellStatus)
                    .frame(width: 480, height: 270)
                    .cornerRadius(8)
                    .opacity(0.5)
                // 屏上诊断面板（LAN 日志不可用时的兜底）：亮白大字，TV 上可读
                ScrollView {
                    Text(shellStatus.isEmpty ? "..." : shellStatus)
                        .font(.system(size: 26, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 1100, height: 400)
                .background(Color(white: 0.12))
                .cornerRadius(12)
                // 焦点意图：ScrollView 内是纯 Text（不可聚焦），焦点不会被长文本劫持
                Text("日志也可 curl http://<ATV-IP>:8765/log")
                    .font(.caption)
                    .foregroundStyle(.green)
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
