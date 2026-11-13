import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v100"
    static let changes = "v100: 回退v94-v99造轮子(猜HEVC/候选池/失败换档/pause静音门控)到v93好状态;照myDV VideoPlayUrlResolver:AVPlayer原生解HEVC,黑屏非HEVC,播放器侧保持干净"
}
