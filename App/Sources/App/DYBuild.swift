import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v176"
    static let changes = "v176: 作者作品翻页修复(真机:首页20+条hasMore=1→第二页17字节空列表;翻myDV u11.F0实锤按端点设referer,页面上下文fetch不能自定义Referer头→history.replaceState切document URL到/user/<secUid>、/collection/、/video/零加载对齐;翻页≥3s节流+空响应body日志+退避重试2次;同作者重开只补缓存不重复请求防限流;postMaxPages 8→20;网格触底主动补页requestMoreWorks)"
}
