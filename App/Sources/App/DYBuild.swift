import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v146"
    static let changes = "v146: ①触摸板手势——上/下滑切换视频(阈值100px)+长按1.5s两倍速播放松开恢复(audioTimePitchAlgorithm=timeDomain不变调);关闭collection原生滚动防打架;②右轨头像正圆修正(cornerRadius=38);③注意:v145的面板/图标尺寸在v145包里,装v146包含全部"
}
