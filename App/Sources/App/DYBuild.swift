import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v5"
    static let changes = "v5: 修复闪退（CGRect 经 objc_msgSend 按 C 约定传 struct，NSAllocateObject 单次初始化）"
}
