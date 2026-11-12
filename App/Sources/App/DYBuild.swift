import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v34"
    static let changes = "v34: hook 全 ASCII 化(去中文注释解静默失败)+HOOK_START 探针信号定位注入问题"
}
