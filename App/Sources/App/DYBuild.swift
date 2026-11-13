import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v114"
    static let changes = "v114: 诊断——dump video消息所有field(号/wire/长度),定位bit_rate真实字段号(bit_rate在21/31取不到,entries空致bitrate-dump不出现)"
}
