import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v108"
    static let changes = "v108: 治翻页黑屏——reloadIfNeeded改增量insertItems(翻页只插新增不动已有cell/player池),废除每次merge全量reloadData摧毁已缓冲player致黑屏;仅首批reloadData建池"
}
