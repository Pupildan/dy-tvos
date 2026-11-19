import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v232"
    static let changes = "v232: TikTok源plan B页面代签fetch(v231实锤tvOS WebKit缺MSE→页面降级渲染无无限feed→滚动/预载判死,唯一可行=页面上下文代签fetch recommend)。hookJS see()捕获页面自己发过的完整recommend URL作模板,无则用兜底模板;只换cursor翻页;调用页面window.fetch(TikTok自己的签名包装器代签X-Argus/X-Gorgon/msToken)→响应流回我们的fetch包装器grab()截获(同DYWorksCapture已验证代签机制);hooked且totalCap==0时每5tick发一轮泵+requestMore也走代签fetch。响应经grab→__ttCap→drain常规抽回,零新增解析"
}
