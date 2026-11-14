import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v141"
    static let changes = "v141: 弹幕间歇显示第二根因=显示吞吐不足(12轨道×9s≈1.3条/s,密集视频2-5条/s超量被noSpaceShoot静默丢弃)→轨道高46→34+显示区55%→75%(约23轨道)+速度300→380px/s+字号38→34,吞吐≈3.3条/s;补dm_drop计数器(noSpaceShoot delegate)量化丢弃,数据说话"
}
