import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v194"
    static let changes = "v194: 修v193 CI编译错 LivePlayerCell引用Self.textShadow但重写时删了该static属性→加回private static let textShadow(NSShadow)。其余同v193: 直播黑屏修=控制器级AVPlayerViewController渲染(v189出画面方案)+v192 asset header(CDN不返回空)正确组合,cell透明只留标题/观看数overlay,视频层浮在collection view下,单AVPlayer换URL保留"
}
