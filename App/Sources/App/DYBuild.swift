import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v147"
    static let changes = "v147: ①确认键修正(.select 点击板中心=呼出快捷面板,.playPause 播放/暂停键恢复暂停切换——v146 误绑);②评论功能实装(web comment/list 探针已验证 status0/55091条,分页cursor 3页60条,评论屏=全屏液态玻璃列表 头像/昵称/文本/赞数/时间,Menu关闭);③作者主页被UIFID风控墙挡住(ArgusSecurityPlugin,myDV同样会blocked)保持占位待后续挖 UIFID 申请链(uz0 POST X-Secsdk-Csrf-Token)"
}
