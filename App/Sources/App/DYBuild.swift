import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v138"
    static let changes = "v138: ①弹幕断流修复——danmaku get_v2 单次响应~460条上限是根因(开发机探针实锤186s视频458/total3564);改60s窗口分段顺序取回合并去重,增量回调段追加,探针实测同视频1183条全量;②面板焦点去系统灰底(自定义ButtonStyle,label原样返回)+焦点行液态玻璃底板+白描边(按用户要求描边也加玻璃质感)"
}
