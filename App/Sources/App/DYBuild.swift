import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v133"
    static let changes = "v133: 弹幕数据链打通——开发机探针实锤 status_code=3 'AppId不合法' 根因=缺web公共参数;修复=请求加device_platform=webapp/aid=6383/channel_pc_web/browser_* + 签名输入含timestamp(webCommon+u11.K参数+timestamp→getABogus→a_bogus后置);authentication_token传空即可(proto无此字段);探针实测12s短视频items=1461;省CI构建轮次(数据链全部开发机先行验证)"
}
