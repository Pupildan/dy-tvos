import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v27"
    static let changes = "v27: 丢弃403的/play/直链(除黑屏)、回归居中不裁切、去测试按钮自动播、泵全屏翻页"
}
