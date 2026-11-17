import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v207"
    static let changes = "v207: 直播黑屏真凶终于抓到——一行代码: playerVC.player 从v193创建以来从未赋值! grep实锤零匹配。sharedPlayer照常出声(item ready/time走/ps=1280x720/errLog空), 但渲染层(AVPVC.view的AVPlayerLayer)没有player→isReadyForDisplay永远0→全屏黑。修: playerVC.player = sharedPlayer。此前v206诊断版AVPlayerItem自带日志(errorLog/accessLog/ps/rfd)立功: 全绿唯独rfd=0+ps有值→锁定渲染层断链而非解码/CDN/编码问题(SPS探针也实锤High/4:2:0/8bit标准流,HEVC假设证伪)"
}
