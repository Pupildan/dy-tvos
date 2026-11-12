import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v48"
    static let changes = "v48: 模板回放直连——pump捕获完整feed URL,原生替换refresh_index/presented_ids重签,shim UA统一"
}
