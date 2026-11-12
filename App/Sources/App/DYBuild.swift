import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v9"
    static let changes = "v9: P2 探测——注入 fetch/XHR hook 抓 Feed API 视频直链,确认 API 直链 vs Blob 分片"
}
