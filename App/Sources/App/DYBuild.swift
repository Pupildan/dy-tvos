import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v97"
    static let changes = "v97: 补黑屏漏洞——默认play_addr兜底路径也过滤api-play慢链(v95只堵了pickHighestQuality,兜底从field1又捡回慢链致黑屏有声)"
}
