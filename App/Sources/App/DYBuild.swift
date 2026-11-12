import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v56"
    static let changes = "v56: 泵导航?recommend=1(myDV主源tab/feed)+双端点模板捕获+签名uri动态化+头竞态修复+入口日志"
}
