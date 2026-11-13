import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v122"
    static let changes = "v122: 播放时现选新鲜URL(照myDV resolveFinalPlayUrl)——PlaybackEngine存rawVideos[index],acquire用rawVideo现跑pickHighestQuality取当下URL,不用预载静态URL;治URL过期黑屏"
}
