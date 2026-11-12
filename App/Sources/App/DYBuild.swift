import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v11"
    static let changes = "v11: 局域网日志服务器(curl :8765/log)+ 屏上诊断面板调亮可读"
}
