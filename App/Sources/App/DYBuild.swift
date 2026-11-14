import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v129"
    static let changes = "v129: 无感跳过图集/novideo——parse 阶段双信号过滤(照 myDV filterPrimaryPlayableAwemes 语义):awemeType!=0(照s13.e:371探字段43/55/61)或 dur=0(v128实锤:两个novideo坏条目 idx=69/82 时长字段全缺)不进池→用户永远刷不到;dur取值链修正(f13提前,f22是标志位非时长);runtime repair→skip 保留兜底;FEED skip-item 逐条记录过滤原因"
}
