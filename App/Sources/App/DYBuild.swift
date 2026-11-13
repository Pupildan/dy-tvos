import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v83"
    static let changes = "v83: 真·双视频图层同时滑动(上一往上/下一从下接)+异步封面兜底防黑帧,连贯不假"
}
