import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v79"
    static let changes = "v79: 双播放器池重构——按键瞬间弹簧滑动(0.35s/damping0.8)+错峰释放解决Cannot Open+封面兜底杜绝黑屏"
}
