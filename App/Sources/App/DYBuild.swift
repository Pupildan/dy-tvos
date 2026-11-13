import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v86"
    static let changes = "v86: 修跳号(didFail防slot重复fire advance)+修启动黑屏(首批失败advance到下一条不卡黑屏)"
}
