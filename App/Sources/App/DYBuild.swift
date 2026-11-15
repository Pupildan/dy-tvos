import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v182"
    static let changes = "v182: 用户实锤myDV全功能免登录→撤回只剩扫码登录的判断,继续找匿名路径。v181日志三大发现: ①CAP post TIME LIST非空(按月分组,如2026·11..2024·06) ②count=100与50同为41条,服务端硬上限~50 ③SESSION page-url抓到页面自己发的原生aweme/post(无count/locate_item_id/version_code=290100,参数集与我们照抄myDV拼的完全不同)。 ①滚动泵修真根因:抖音PC作者页用内部overflow容器,v163-v181只滚window从未触发无限滚动→遍历div/ul/section/main/aside/article所有可滚动元素逐个滚到底+派发scroll ②hook保留页面原生post完整URL(1200字符)分片打PAGE POST URL[n]并保存模板 ③新增pageTemplatePagedURL:逐字节照抄页面自己的参数集,只改max_cursor/need_time_list,删动态签名交页面重签,首屏hasMore时并行试一次(不刷屏) ④换作者/teardown清空模板状态"
}
