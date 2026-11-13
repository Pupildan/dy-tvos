import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v63"
    static let changes = "v63: 照抄 s13.a 修 urlList 提取——http URL 在 play_addr field 2(非 field 1 的 uri),优先级 field2→递归→field1"
}
