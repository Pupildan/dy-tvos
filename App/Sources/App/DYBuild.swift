import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v126"
    static let changes = "v126: KVO失败/无视频轨跳过——playerItem.observe防item遮蔽,failed或无视频轨直接engine.next()精确+1(isCurrent防误跳),治黑屏有声/无声且不跳多页"
}
