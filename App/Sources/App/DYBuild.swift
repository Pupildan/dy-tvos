import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v101"
    static let changes = "v101: 治频繁卡住有声——load换item后pause+静音,updatePlaybackStates居中槽仅readyToPlay才play(保留v94/96对症门控,剥v95-99造轮子)"
}
