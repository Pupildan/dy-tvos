import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v197"
    static let changes = "v197: 修v196 CI编译错 .AVPlayerItemDidPlayToEnd符号在当前SDK解析不到(v195 object可选/v196 if let item 两写法都报NSNotification.Name?无此成员)→改字符串字面量NSNotification.Name(\"AVPlayerItemDidPlayToEnd\")构造通知名绕开符号解析,object传player。其余同v195: 图标修(删top-shelf错尺寸槽位+删AccentColor)+启动加载视频过渡(LaunchVideoOverlay静音循环遮黑屏,首帧ready交叉淡化0.6s掉overlay)"
}
