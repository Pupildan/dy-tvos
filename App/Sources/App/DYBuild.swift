import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v193"
    static let changes = "v193: 修v192直播黑屏。日志铁证v192 ready=1 status=1 playing但黑屏=我把出画面的AVPlayerViewController换成了手动PlayerLayerView(AVPlayerLayer),正是v186/v187黑屏老路;v189出画面靠AVPlayerViewController。正确组合=控制器级AVPlayerViewController渲染(v189出画面方案)+v192 asset header(CDN不返回空),这组合没试过。改:删LivePlayerCell的playerLayerView/cover(cell不渲染视频,透明背景),视频改控制器级AVPlayerViewController渲染浮在collection view下,cell只留标题/观看数overlay。保留单AVPlayer换URL(v192)+滑动切房动画不动"
}
