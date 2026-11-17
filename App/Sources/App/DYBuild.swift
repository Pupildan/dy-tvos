import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v196"
    static let changes = "v196: 修v195 CI编译错 RootView.swift:146 .AVPlayerItemDidPlayToEnd报NSNotification.Name?无此成员→object传player.currentItem(可选)污染成员查找;改成先if let item=player.currentItem捕获局部非可选,object传item。其余同v195: 图标修(删top-shelf错尺寸槽位+删AccentColor)+启动加载视频过渡(LaunchVideoOverlay静音循环遮黑屏,首帧ready交叉淡化0.6s掉overlay)"
}
