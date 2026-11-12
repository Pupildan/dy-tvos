import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v60"
    static let changes = "v60: v2/feed 返回 protobuf 非 JSON——加手工 proto wire 解码器(s13 字段号)提取 url_list,修复卡加载态"
}
