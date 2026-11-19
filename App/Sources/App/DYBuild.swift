import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v233"
    static let changes = "v233: 修TikTok plan B翻页墙(真机v232画面出但刷不动)。根因=fireProxyFetch completion里 s.hasPrefix(\"ok\") 判据永假(JS返回 'fired…' 非 'ok…')→proxyCursor恒0→每次requestMore重取cursor=0→同批被seenIds去重→引擎零增长。修=游标推进移到drain按实际到货条数推进(只对proxy<N>批, max单调防乱序回退)+fireProxyFetch加≥1.5s节流防触底连发+pump门控收紧为只播种首批(totalCap==0&&proxyCursor==0)翻页全交engine requestMore"
}
