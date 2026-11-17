import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v190"
    static let changes = "v190: 修直播刷很多个只一个房间出画面其余黑屏(有声音)。v189日志铁证同房间player被反复销毁重建(idx=0出现3次)→根因prepareWindow每次滚动把窗口[idx-1,idx+1]外player replaceCurrentItem(nil)+从字典删除(照抄VOD解码器回收),刷回来ensurePlayer见字典空就createPlayer重建→HLS直播重新缓冲→黑屏(有声音=新player在缓冲),只当前居中那个刚好活着出画面。修:加playerCache(webRid→AVPlayer)驱逐只pause不销毁,ensurePlayer先查cache复用已缓冲player秒出画面,createPlayer存cache+超上限8淘汰最旧不在窗口的释放解码器。AVPlayerViewController出画面保留(v189已验证)"
}
