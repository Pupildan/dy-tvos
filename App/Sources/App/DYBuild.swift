import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v123"
    static let changes = "v123: 黑屏看门狗——每1.5s查居中player视频时间是否前进,连续2次停滞判定黑屏跳下一条;修v122被切坏的viewDidLoad结构"
}
