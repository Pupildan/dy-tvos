import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v117"
    static let changes = "v117: 焦点隔离实验——PlayerCell加canBecomeFocused=false+isUserInteractionEnabled=false排除出焦点系统,验证跳多页是否焦点引擎作怪(基于v114)"
}
