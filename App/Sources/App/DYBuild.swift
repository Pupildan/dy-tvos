import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v113"
    static let changes = "v113: 诊断bit_rate结构——dump首条所有field(号/wire/长度),确认is_h265/play_addr真实字段号,为H264优先做准备"
}
