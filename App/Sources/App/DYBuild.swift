import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v169"
    static let changes = "v169: 修v168作品网格焦点不可点(tvOS焦点引擎要求ScrollView内Button绑@FocusState,评论屏v148同款教训,workCell加.focused绑定);播放层合集标记(发布时间后金黄▦+合集名,mobile=f14/web=mix_info/截获作品=JS mix字段全打通);作品网格封面加▦合集角标;JS精简提取mix_info.mix_name"
}
