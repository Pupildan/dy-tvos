import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v107"
    static let changes = "v107: 治池抖动黑屏——prepare只从scrollTo调一次(去updatePlaybackStates重复调用),窗口放宽current±2,willDisplay用peekPlayer纯查询不撑池;杜绝acquire/evict横跳驱逐刚ready的player"
}
