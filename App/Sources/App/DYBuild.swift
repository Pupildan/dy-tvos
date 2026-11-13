import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v75"
    static let changes = "v75: 修无声(静音只作用备用槽)+修清空竞态(只清非相邻且非加载中的槽,防Cannot Open黑帧)+loadingIndex追踪"
}
