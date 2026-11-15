import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v178"
    static let changes = "v178: 作者作品翻页换路线(v175参数对齐/v176referer/v177fragment连续3版均status_code:0软拒,判死自拼URL): ①请求URL彻底净化,标记只存JS本地__dyTagMap不再进query/fragment(fragment仍会被页面签名包装算进URL字符串) ②改XHR优先发请求吃页面jsvmp签名包装(fetch通道此前可能压根没签名,首页宽松翻页严格),空响应自动fetch补一枪 ③离屏WebView 1x1→1920x1080真实viewport+作者页真导航+2.5s滚动泵,让页面自己发懒加载翻页(参数与签名全由页面生成;v163起1x1滚动永不触发=分页从未成功的遗留真根因) ④hook保留完整原生aweme/post URL分片打日志,翻页参数1:1照抄该模板(删动态签名交页面重算) ⑤软拒不再判死hasMore,交给页面原生通道继续"
}
