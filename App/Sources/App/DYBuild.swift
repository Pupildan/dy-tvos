import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v87"
    static let changes = "v87: 修跳号(onFailed去掉reportFailure双推进,只走advance)+修声画不同步(滑动起步瞬间静音旧槽出新声)"
}
