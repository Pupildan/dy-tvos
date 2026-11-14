import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v132"
    static let changes = "v132: 弹幕功能上线——数据照抄myDV u11.K(web /aweme/v1/web/danmaku/get_v2/)+u11.A(ttwid匿名注册,无需登录);渲染vendor DanmakuKit(MIT,Core Animation,tvOS兼容已确认)按播放时钟发射;探针版:authentication_token/group_id proto字段号未知(aweme-dump探针同跑),token先传空,端点可用性由DANM日志实锤"
}
