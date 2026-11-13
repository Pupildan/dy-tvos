import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v93"
    static let changes = "v93: 修刷不动——scrollTo对齐engine.index并接近末尾triggerNeedMore翻页(此前setContentOffset绕过翻页链路,刷完首批6条卡死)"
}
