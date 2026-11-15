import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v153"
    static let changes = "v153: ①悬停倍速纯计时触发:手势共存委托(shouldRecognizeSimultaneouslyWith)——v149-v152 LongPress 被 pan 的默认互斥规则在手指移动10px时强杀,纯静止触摸永远到不了0.6s;共存后静置即触发,pan通道保留兜底;②按用户要求撤销黑边取色模糊背景;③作者主页实装:挖通myDV身份链——UIFID_TEMP由tab/feed响应Set-Cookie下发+cookie罐收集,uifid参数/头+x-secsdk-web-signature(MD5密钥A96D..,u11.i照抄,探针签名验证通过),user/profile/other匿名全通(昵称/粉丝/作品数);主页屏(头像/昵称/四格统计/简介);作品列表aweme/post探针仍200空(Node TLS指纹疑点),真机URLSession试探已埋日志"
}
