import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v210"
    static let changes = "v210: 直播黑屏-锁定真根因=AVPlayer直播追边stall,修v209失效seek-back。v209渲染树+ffprobe终极判定: 平铺TS滑动窗口下载2.9MB ffprobe轻松解出H.264 High@L4.0 1080x1920视频轨+AAC,清单标准非嵌套,渲染树AVPlayerLayer满屏挂载全好→唯独AVPlayer卡-16832 stall不解首帧(ps=0x0/rfd=0)。v209的seek-back写在readyToPlay KVO里那刻seekableTimeRanges还没填充→count=0一次没触发。修: ①sharedPlayer.automaticallyWaitsToMinimizeStalling=false(直播标准修法,默认true等缓冲又追不上边缘→反复重启) ②preferredForwardBufferDuration=4s ③失效status-KVO换成pollAndSeekBehindLiveEdge轮询(0.5s间隔最多20次)等ranges填充后seek到边缘后方10s稳定点。v209的rfd递归找真layer+渲染树dump保留"
}
