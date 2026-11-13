import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v110"
    static let changes = "v110: 回退到v76稳定底座——单AVPlayer+快照遮罩滑动(单解码器原子换源,遮罩盖空窗),根除池架构黑屏/冻屏/跳号/残留;tvOS按键导航下遮罩滑出即切换滑动效果"
}
