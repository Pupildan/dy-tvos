import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v119"
    static let changes = "v119: 治黑屏无声——readyToPlay后查item.tracks(视频)为空(图集/纯音频)则skipFailed跳过;删无效awemeType过滤(field6非awemeType空操作)"
}
