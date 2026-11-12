import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v30"
    static let changes = "v30: 自动播首条+接近末尾触发翻页+过期/连续失败重拉(解无限刷/上键过期/手动切)"
}
