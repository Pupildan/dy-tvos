import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v62"
    static let changes = "v62: PROTOTREE 显示 field7/8 是 author 头像非 video——改用 topSkeleton 列 aweme 顶层字段骨架,定位真实 video 字段号"
}
