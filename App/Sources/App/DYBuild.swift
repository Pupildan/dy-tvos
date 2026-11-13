import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v95"
    static let changes = "v95: 修有声无画面——pickHighestQuality过滤api-play//aweme/v1/play/慢重定向链(视频轨道不解码→黑屏),只留CDN直链"
}
