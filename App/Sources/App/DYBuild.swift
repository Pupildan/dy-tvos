import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v188"
    static let changes = "v188: 修直播黑屏(有声音无画面)。日志铁证ready=1 playing=1 layer=1920x1080全绿却黑屏=手动管AVPlayerLayer渲染在这条链断了,连败v186(KVO ready)+v187(frame诊断)两轮→按铁律回退标准底座:直播cell从PlayerCell(手动AVPlayerLayer)换成LivePlayerCell(内嵌AVPlayerViewController,它自己render天生出画面)。保留纵向分页/滑动切房/遥控上下键/游标无限翻页/池窗口/HLS,只换出画面那一环。showsPlaybackControls=false不干扰上下键切房"
}
