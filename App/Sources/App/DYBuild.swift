import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v77"
    static let changes = "v77: UICollectionView垂直分页+3实例PlayerPool——真实视频图层滑动(UIScrollView物理惯性),遥控setContentOffset,Cell划出不销毁播放器循环复用"
}
