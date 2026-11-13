import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v90"
    static let changes = "v90: 定位提取循环崩溃——逐条埋日志+urlList递归加上限;删除launch_video.mp4提速"
}
