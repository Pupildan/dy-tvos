import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v25"
    static let changes = "v25: 竖版视频居中不裁切+背景模糊（遵守原始约束），双层同源AVPlayer同步"
}
