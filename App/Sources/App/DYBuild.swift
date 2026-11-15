import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v167"
    static let changes = "v167: 修v166 CI编译错——DYProfileScreen是struct无法遵循class协议(Delegate:AnyObject),去掉AnyObject约束+delegate改strong(struct非weak目标,单例+View生命周期内注册无循环引用);其余同v166(WebView截获profile接UI,DYProfileScreen改吃截获数据源弃用被200空拒的原生fetch)"
}
