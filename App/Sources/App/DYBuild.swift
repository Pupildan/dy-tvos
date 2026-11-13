import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v67"
    static let changes = "v67: VIDEOTREE dump——移动端 video field21 是 varint 非 bytes,与网页版 s13 不符;dump 真实结构定位 bit_rate"
}
