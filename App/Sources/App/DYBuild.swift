import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v135"
    static let changes = "v135: 设置面板上线——Menu呼出(第二次按=退出应用);屏幕左侧悬浮iOS26液态玻璃(tvOS26 glassEffect,低版本ultraThinMaterial回退);五项:移动端推荐(现源)/抖音精选(web tab/feed b0配方+webCommon,开发机探针已验证status0分页正常)/弹幕设置(开关)/直播+登录(占位);双源架构:engine.reset+PlayerManager按源选请求头(web=ChromeUA+Referer+ttwid)"
}
