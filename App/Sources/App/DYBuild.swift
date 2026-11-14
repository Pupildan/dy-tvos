import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v148"
    static let changes = "v148: ①评论屏闪退修复:tvOS焦点环境无可聚焦元素致异常(真机日志实锤 select comment 后 ROOT auto-start)——评论行改可聚焦Button+常驻返回按钮+关面板后0.4s再开评论屏;②两倍速改长按确认键0.6s触发松开恢复(撤销v146触摸板长按,短按仍是呼出快捷面板);③快捷面板改屏幕底部居中横向卡片排列;④右轨4图标加大(46pt符号/68高/头像88正圆)"
}
