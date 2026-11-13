import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v71"
    static let changes = "v71: 双播放器池(A/B Layer 垂直滑动秒切)+内存纪律(预载buffer3s/后台静音/滑出clear防溢出)"
}
