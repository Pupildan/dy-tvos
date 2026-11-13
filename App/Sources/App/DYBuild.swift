import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v94"
    static let changes = "v94: 修画面冻结有声——scrollTo起步即暂停非目标槽,load换item时静音+暂停,updatePlaybackStates居中槽解除静音出声(声画同步)"
}
