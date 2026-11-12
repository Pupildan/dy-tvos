import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v56"
    static let changes = "v56: 修头竞态(首请求早于头入库被拒)+fetchNativePage入口日志+移除回放探针"
}
