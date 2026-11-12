import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v57"
    static let changes = "v57: 页面视频静音但播放(不pause)——feed播放进度驱动自我推进,解决翻页停滞"
}
