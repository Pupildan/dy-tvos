import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v96"
    static let changes = "v96: 修有声画面冻结复发—— currentItem.status KVO 等 readyToPlay 且仍是当前槽才 play,不再靠固定延时赌解码时机"
}
