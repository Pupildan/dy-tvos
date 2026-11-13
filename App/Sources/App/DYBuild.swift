import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v99"
    static let changes = "v99: 治黑屏——播放器侧兜底:parse收集每条多CDN候选,item .failed时KVO自动切备用档重试(不猜编码字段)"
}
