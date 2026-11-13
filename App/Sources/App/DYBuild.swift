import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v88"
    static let changes = "v88: 启动视频加载动画(launch_video.mp4全屏循环静音,feed就绪淡出,替代文字Loading)"
}
