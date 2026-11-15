import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v174"
    static let changes = "v174: ①DYWorksCapture重构=持久会话+全页面上下文fetch泵(真机实锤:网页滚动分页从未成功/每开作者页都新建会话慢/会话互踩;一次会话过挑战,profile/aweme-post/mix全用_dytag标记fetch,hasMore自动排队下一页max_cursor,空闲30s/180s收摊,裸JSON兜底解析) ②点播语义定版(用户拍板):段插入回归=未操作自动刷作者作品段/合集段刷完自动回feed,快捷面板新增「回到推荐」项(段激活时显示)立即removeWorksSegment推回正常流"
}
