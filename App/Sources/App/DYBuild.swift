import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v103"
    static let changes = "v103: 治黑屏增多——撤updatePlaybackStates的readyToPlay门槛,居中槽无条件play+解除静音(AVPlayer没ready会自缓冲,挡死它才黑屏);留load换item pause+静音+KVO兜底"
}
