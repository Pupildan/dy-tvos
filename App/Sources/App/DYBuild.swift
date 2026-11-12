import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v58"
    static let changes = "v58: 彻底转 myDV 移动端 /aweme/v2/feed/ 直连(4 参签名+安卓 UA+refresh_index 游标),删除全部 WebView 泵/网页 module/feed 逻辑"
}
