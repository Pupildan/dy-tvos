import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v143"
    static let changes = "v143: PC版UI上线(参考web版布局)——右轨:上下切换箭头+作者头像+点赞/评论/收藏/分享计数(万缩写);左下:头像+@昵称+文案+话题;数据=mobile proto 实测字段(desc=f2 hashtags=f459 author=f4 stats=f10 f3赞f2评f6享f11藏)+web JSON直取;计数纯展示,随视频自动切换;弹幕任务已暂停记录待重启"
}
