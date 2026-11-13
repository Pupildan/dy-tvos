import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v82"
    static let changes = "v82: 快照滑动极致平滑——弹簧动画(damping0.85)+背景缩放1.05→1.0补偿+未Ready显Loading圈"
}
