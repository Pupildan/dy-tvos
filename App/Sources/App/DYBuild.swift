import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v91"
    static let changes = "v91: 修启动闪退——scrollToItem 在 flow layout 未算出 contentSize 时抛 NSException(.ips已定位),加 canScrollTo 守卫(layoutIfNeeded+numberOfItems)"
}
