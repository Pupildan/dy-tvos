import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v70"
    static let changes = "v70: 末帧快照遮罩(AVAssetImageGenerator 截当前帧铺满)+ readyToPlay 后延迟100ms淡出,消灭单AVPlayer换源黑帧"
}
