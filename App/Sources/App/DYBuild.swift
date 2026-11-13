import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v64"
    static let changes = "v64: 最高画质(bit_rate field21/31 按 h*w→fps→码率取最大)+ 无缝切换遮罩(换源盖黑,readyToPlay 后0.2s淡出)"
}
