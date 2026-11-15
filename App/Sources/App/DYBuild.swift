import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v159"
    static let changes = "v159: ①触摸悬停最终删除(图上方案真机仍不触发,恢复v156手势:纯滑动+确认键长按);②主页深挖重大进展:反编译classes2/3.dex拿到myDV完整UI层——作品=aweme/post、作者合集列表=series/list(sec_user_id,已探针全通)、合集内容=series/aweme/aweme/detail;③发现myDV z()引导(u11:5400):首页GET手动跟随重定向5跳吸收信任cookie+y()解析HTML取msToken/odin_tt/user_unique_id(webid)——Node必被jsvmp挑战页拦,真机URLSession是否被拦v159定论(引导已装,日志PROFILE boot行);④D0补verifyFp/fp/webid参数"
}
