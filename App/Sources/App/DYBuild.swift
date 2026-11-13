import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v112"
    static let changes = "v112: 治一次按键跳多页——failedIndices记已跳过index,重复failed不再advance(断级联);prepare窗口跳过已失败index不再反复acquire;日志实锤idx=103反复acquire/failed驱动advance一秒跳5页"
}
