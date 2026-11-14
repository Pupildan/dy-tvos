import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v137"
    static let changes = "v137: 视频源持久化——用户选过的源存 UserDefaults(dy_feed_source),下次启动直接用上次设置过的源(面板徽标同步);源切换真机验收已通过(web ready x10)"
}
