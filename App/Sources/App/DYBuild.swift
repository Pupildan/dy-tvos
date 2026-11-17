import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v205"
    static let changes = "v205: 修v204 CI编译错 errorLog/accessLog在此SDK是方法且返回Optional(不是属性)→item.errorLog()/item.accessLog()解包调用。其余同v204: AVPlayerItem自带诊断(errorLog/accessLog/presentationSize/isReadyForDisplay/轨道数) play后3s+8s dump LIVE DIAG行"
}
