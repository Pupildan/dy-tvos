import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v191"
    static let changes = "v191: 修v190回归(只第一个房间出画面,刷后面连声音都没)。v190日志铁证idx=2/idx=4卡ready=0 playing=0 status=0永不ready→根因prepareWindow驱逐时readyObservers[i].invalidate()掐死ready观察,快速滑动player刚建没ready就划出窗口→invalidate后player后来ready了没人接→永远status=0。修:readyObservers改按webRid键(原按index),驱逐别invalidate(player在playerCache活着观察保持armed),只在evictPlayerCacheIfNeeded真销毁时invalidate防泄漏;ensurePlayer复用/createPlayer已armed别重挂防重复观察泄漏。playerCache复用保留(v190)"
}
