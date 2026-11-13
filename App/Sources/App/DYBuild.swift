import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v66"
    static let changes = "v66: 加 QDIAG 诊断——video 字段骨架+bit_rate 每档详情,定位最高画质为何未命中(黑屏/非高清同源:默认重定向地址)"
}
