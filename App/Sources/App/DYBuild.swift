import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v61"
    static let changes = "v61: 播放失败(unsupported URL)——加递归 proto 树 dump,定位 url_list 真实字段号"
}
