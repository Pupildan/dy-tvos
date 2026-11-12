import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v35"
    static let changes = "v35: U-S1 签名器探针——JSContext 本地跑 myDV 签名 JS(bdms+shim)，验证 getABogus 可行性"
}
