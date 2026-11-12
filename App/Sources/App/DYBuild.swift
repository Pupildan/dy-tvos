import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v18"
    static let changes = "v18: 方向A——hook 批量 dump 抖音所有 fetch/XHR 请求 URL，定位 feed 接口"
}
