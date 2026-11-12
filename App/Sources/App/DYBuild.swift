import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v33"
    static let changes = "v33: 修首条自动播(currentIndex提前提交bug)+真实滚动容器Wheel/Touch+哨兵scrollIntoView+网页视频静音"
}
