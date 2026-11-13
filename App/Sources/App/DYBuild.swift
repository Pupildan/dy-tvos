import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v105"
    static let changes = "v105: 治黑屏——configure加复用守卫(已装载同一index且player在则复用不重建),防reloadData/重复cellForItemAt销毁已缓冲player致居中瞬黑屏"
}
