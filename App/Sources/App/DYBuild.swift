import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v28"
    static let changes = "v28: 主动翻页——hook 用页面 fetch 调 feed 接口 refresh_index 递增（验证签名需求）"
}
