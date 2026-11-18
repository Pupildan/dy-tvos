import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v212"
    static let changes = "v212: 直播播放内核 AVPlayer→KSPlayer(KSMEPlayer/FFmpeg软解)。铁律只有直播内核能换(VOD/主feed/loading 一律不动)。依据: v185→v211十几轮实锤 AVPlayer对抖音直播HLS卡-16832追边stall永解不出首帧(ffprobe啃本地TS证实流/编码/清单/渲染层全好, 唯独AVPlayer这内核的live-edge逻辑救不了)。换KSMEPlayer(FFmpeg独立HLS demuxer)绕开AVPlayer整套live-edge。接入: ①project.yml加第一个SPM依赖KSPlayer 2.3.4(会传递拉FFmpegKit 6.1.4) ②DYLiveUI删sharedPlayer/playerVC/resolvePlaylist/findPlayerLayer/dumpRenderTree, 改用KSVideoPlayer.Coordinator.makeView(url:options:)(幂等,换房=再调一次makeView换流) ③KSOptions.firstPlayerType=KSMEPlayer.self锁FFmpeg(落回KSAVPlayer=换汤不换药) ④isLoopPlay=true断流重连 ⑤onStateChanged/onPlay(节流5s防0.1s定时器刷爆日志)/onFinish回调替代原LIVE DIAG, .bufferFinished=画面渲染中代理信号。保留全部滑动/遥控切房/焦点/翻页逻辑不动"
}
