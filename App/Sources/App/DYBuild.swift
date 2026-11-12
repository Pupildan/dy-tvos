import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v29"
    static let changes = "v29: 原生Loading动画+首批自动播index0+真实scroll/touch事件触发抖音翻页(混合模式)"
}
