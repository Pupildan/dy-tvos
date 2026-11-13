import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v102"
    static let changes = "v102: 治黑屏/冻屏——currentItem.status KVO ready即自动play(不靠滚动离散触发),保留load换item pause+静音门控;剥v95-99造轮子"
}
