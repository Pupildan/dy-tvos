import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v104"
    static let changes = "v104: 废除3-player池改派——每Cell独占AVPlayer,显示哪个播哪个永不换URL,复用时销毁;根除换源空窗(黑屏/冻屏病根),保留真实视频层滑动铁律"
}
