import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v185"
    static let changes = "v185: 修 v184 CI 编译错 DYLiveClient.swift:148 has_more 解析 Bool?/Int? 混型(?? 链里 Bool? 和 Int? 不能混)→探针实锤 has_more 恒 Bool,简化为 (as? Bool) ?? true。其余同 v184: 直播全屏纵向分页刷直播间+无限加载,游标=extra.max_time 实锤,链式4页累积36去重房间。DYLiveClient游标翻页+DYLiveUI纵向分页器(照抄NativePlayerView分页/手势/遥控/池窗口)+PlayerCell.configureLive"
}
