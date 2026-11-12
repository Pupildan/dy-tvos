import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v36"
    static let changes = "v36: shim 去 NUL 毒字节(解析失败根因)+JSContext 异常检测修复+推送日志历史回灌"
}
