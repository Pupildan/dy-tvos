import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v220"
    static let changes = "v220: 直播弹幕三处优化(真机截图反馈)。①表情包图片加载改并发(214张DispatchGroup并行几秒完成,原顺序下载20s+太慢→表情显示不出来); ②弹幕字体/行距减小(fontSize 26→22,行高52→44,间距6→4,表情图34→28,不影响观看); ③标题/简介移到视频区左上角(原左下角)+字体减小(昵称32→26/简介26→22, layoutSubviews改infoTop=vr.minY+24顶部对齐)。视频区videoRect自适应定位(v219)保留。铁律只动直播, VOD弹幕/main feed/loading不碰"
}
