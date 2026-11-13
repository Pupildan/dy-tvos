import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v98"
    static let changes = "v98: 治黑屏(HEVC)——pickHighestQuality按CDN URL启发式降权HEVC/H.265档,优先H.264/AVC(tvOS解不出部分HEVC视频轨)"
}
