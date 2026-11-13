import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v65"
    static let changes = "v65: 修 pickHighestQuality 类型错(bytesFields 已返回[[UInt8]],去掉多余Array/parse)"
}
