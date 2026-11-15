import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v180"
    static let changes = "v180: 翻页墙实锤后换路线(v179真机:max_cursor=0→完整20条2.7MB,任何max_cursor!=0含换游标值/换cursor键/need_time_list=0三变体→一律17字节status_code:0;与HANDOVER§5.3的aweme/post签名/会话信任墙同源,继续调参数是死路): ①彻底停止自拼翻页请求(不再发max_cursor!=0,避免风控),更多作品完全交给页面作者页自己的无限滚动(hook的page-req通道按id去重累积) ②真导航到作者页但修好v178竞态(导航时清队列/记时刻/重置hook稳定计数,drain必须距导航>=2.5s且新document连续2次hooked=1才fire) ③离屏WebView加入window最底层(alpha0.01/不可交互,仍属数据泵)让作者页列表真实渲染,IntersectionObserver与滚动泵才可能触发页面原生翻页 ④首屏count20→50(照myDV u11可变count,绕开翻页墙一次多拿) ⑤空响应不再fetch补枪(双通道重复消耗变体+加速风控) ⑥新增SESSION PAGE-NATIVE PAGING验收日志"
}
