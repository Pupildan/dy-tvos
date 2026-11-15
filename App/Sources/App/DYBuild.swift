import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v170"
    static let changes = "v170: 修v169真机三连——①点作品不播放(真根因=playWork只改engine.index没通知collection,下一按reconcile循环把index退回去,ENGINE prev连环实锤;发DYWorksJump通知播放层scrollTo) ②网格聚焦无视觉效果(白描边+微放大+首批到达自动聚焦第一个作品) ③自动加载剩余作品不生效(首批即teardown真凶;改累积去重+持续滚动截获,增长停滞15s/60s收摊)"
}
