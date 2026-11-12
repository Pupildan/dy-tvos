import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v46"
    static let changes = "v46: 删除单行脚本中的4条//注释(吞掉后续全部代码的总根因,Node前缀扫描定位)"
}
