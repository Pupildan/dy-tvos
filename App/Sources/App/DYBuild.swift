import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v211"
    static let changes = "v211: 直播-回退v210回归(声音画面全没了)。v210真机日志实锤回归: t=0.0时间冻结/status=0 Unknown/seek-poll全give up(20次无seekableTimeRanges count=0死代码)。罪魁=automaticallyWaitsToMinimizeStalling=false把唯一还在工作的声音也弄没了(默认true才等够缓冲再走v209有声音)。回退: ①删automaticallyWaitsToMinimizeStalling=false ②删item.preferredForwardBufferDuration ③删pollAndSeekBehindLiveEdge死代码,回到v209播放路径。保留v209的findPlayerLayer递归真rfd+dumpRenderTree渲染树诊断。结论: ffprobe实锤流/编码/清单/渲染全好,真根因=AVPlayer直播追边stall,但v210的暴力修法是回归,需换思路(参考myDV走FLV/换播放内核)"
}
