import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v81"
    static let changes = "v81: 回退到 v76 稳定单播放器+快照遮罩底座(放弃脆弱双播放器池,恢复刷视频/消除黑屏)"
}
