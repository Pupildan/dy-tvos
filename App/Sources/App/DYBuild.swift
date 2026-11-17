import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v187"
    static let changes = "v187: 直播没画面只有声音-诊断版。加LIVEFEED state日志(居中cell的playerLayer frame/cell frame/ready/playing/status)+willDisplay日志(bind后强制layoutIfNeeded重设frame,打layer尺寸)。有声音=AVPlayer在放,没画面=AVPlayerLayer没render,三假设:A.frame=0 B.status永不ready/cover盖住 C.play没触发。日志区分后定修法"
}
