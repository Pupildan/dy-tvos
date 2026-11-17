import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v206"
    static let changes = "v206: 修v205 CI编译错 loadTracks回调在此SDK是双参数([AVAssetTrack]?, Error?)→闭包加第二参数。其余同v205: AVPlayerItem自带诊断errorLog()/accessLog()/presentationSize/isReadyForDisplay/轨道数 play后3s+8s dump LIVE DIAG行"
}
