import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v118"
    static let changes = "v118: 照抄myDV isPrimaryAweme过滤图集帖——aweme field 6(awemeType)!=0跳过不进池,治黑屏有声(图集无有效视频轨);字段号实测Aweme$$serializer index6"
}
