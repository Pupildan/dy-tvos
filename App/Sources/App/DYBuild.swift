import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v192"
    static let changes = "v192: 推倒per-cell player池(连败v189/v190/v191三轮),照myDV反编译+VOD出画面代码改单AVPlayer换URL。agent翻反编译实锤:myDV整个滑动会话只有一个ExoPlayer(ij4.c全局共享),换房setMediaItem(newUrl).prepare()换URL无池;我建per-cell池多player抢解码器→大部分黑屏。且VOD出画面(NativePlayerView:423)用AVURLAsset带AVURLAssetHTTPHeaderFieldsKey(Referer+UA+ttwid),我直播用裸AVPlayerItem(url:)没带header→CDN返回空→黑屏(有声音=部分CDN宽松)。修:删players池/playerCache/evict/readyObservers/prepareWindow/ensurePlayer/createPlayer整套,加控制器级sharedPlayer单实例,playRoom resolve HLS→AVURLAsset带liveHeaders→replaceCurrentItem换URL→play;LivePlayerCell简化只bind共享player渲染。滑动切房动画层不动(用户核心关切)"
}
