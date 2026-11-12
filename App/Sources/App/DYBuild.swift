import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v37"
    static let changes = "v37: 修正加载顺序——去掉独立 bdms.js(与abogus_dy双定义冲突_v[2]undefined)，对齐myDV运行时"
}
