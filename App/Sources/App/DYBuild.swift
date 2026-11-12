import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v23"
    static let changes = "v23: 播完/失败自动跳下条(解卡黑屏)、预加载前后2条、铺满全屏、泵自动滚动无限刷"
}
