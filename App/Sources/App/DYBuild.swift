import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v172"
    static let changes = "v172: ①右轨4按钮数据(playWork没填statistics;JS提取statistics赞/评/藏/享→DYCapturedWork→DYVideoInfo) ②回不到推荐流(作品段append尾部横在feed后面;改insertWorks插入式重建=已看feed前缀+作品段+feed剩余,down刷完作品自动滑回推荐流) ③合集实装(DYVideoInfo补mixId mobile=f14f6/web=mix_info;快捷面板合集项→DYMixScreen;DYWorksCapture.fetchMix页面上下文fetch mix/aweme吃页面签名包装,hook拦响应→网格点播,§5.3⑤A路线首次实装)"
}
