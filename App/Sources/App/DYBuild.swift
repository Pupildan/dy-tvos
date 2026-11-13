import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v68"
    static let changes = "v68: VIDEOTREE 定位——video play_addr 优先 field 8(直连 douyinvod 720p)退化 field 1(重定向 540p),提画质+消黑屏"
}
