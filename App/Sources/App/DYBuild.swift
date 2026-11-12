import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v6"
    static let changes = "v6: ObjC shim 桥接（CGRect/objc_msgSend 在 .m 内完成，绕开 Swift 限制）"
}
