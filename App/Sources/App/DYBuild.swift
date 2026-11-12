import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v54"
    static let changes = "v54: hook 捕获页面真实请求头(setRequestHeader/fetch headers)——对照网关拒绝的真实差异"
}
