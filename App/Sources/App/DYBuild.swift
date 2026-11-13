import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v120"
    static let changes = "v120: 治黑屏无声变多——删v119误加的无视频轨检测(tracks未加载完误返回空→skip好视频),恢复v111干净readyToPlay→onPlayerReady;保留failedIndices防级联"
}
