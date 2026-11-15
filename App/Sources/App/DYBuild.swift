import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v168"
    static let changes = "v168: 作品网格+点击播放——①修v167作品parse fail根因(JS端预解析精简aweme/post响应只传id/desc/封面/直链/duration,300KB截断不再发生);②DYCapturedWork模型+delegate作品回调;③DYProfileScreen作品网格(3列封面+标题,图集标记);④点击作品merge进PlaybackEngine+跳index+关主页屏回播放;⑤busy,skip修为同作者静默去重/换作者重启捕获"
}
