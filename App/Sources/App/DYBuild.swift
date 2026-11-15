import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v166"
    static let changes = "v166: 作品/资料截获接UI——DYWorksCapture解析截获的profile/other响应成DYProfileUser经delegate喂DYProfileScreen(v165真机截获成立POST len=60000);DYProfileScreen改吃WebView截获数据源弃用被200空拒的原生fetch链;body上限60000→300000(60KB是日志截断真作品JSON约212KB);主页资料+作品数真机可用,作品网格待下版本"
}
