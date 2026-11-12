import SwiftUI

/// 顶层视图。U0 阶段只显示版本号，验证"能装能开"。
/// 焦点意图：本屏无任何可聚焦控件（纯静态文本），Focus Engine 无目标，遥控器滑动无响应属预期。
/// U1 接入 feed 列表时，列表项用 .focusable()/.focusSection() 显式参与焦点。
struct RootView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("DYTV")
                .font(.system(size: 64, weight: .bold))
            Text(DYBuild.version)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("最小闭环搭建中")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
