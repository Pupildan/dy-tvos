import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v17"
    static let changes = "v17: 推送自愈（未 ready 累计尝试后拆掉重连，解 .waiting 卡死）"
}
