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
                WebKitShellView(statusText: $shellStatus)
                    .frame(width: 640, height: 360)
                    .cornerRadius(12)
                ScrollView {
                    Text(shellStatus)
                        .font(.system(size: 20, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 1000, height: 280)
                .background(.quaternary)
                .cornerRadius(12)
                // 焦点意图：ScrollView 内是纯 Text（不可聚焦），焦点不会被长文本劫持
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
