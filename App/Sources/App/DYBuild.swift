import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v124"
    static let changes = "v124: 编码诊断+黑屏看门狗——CODEC日志查视频轨编码(确认是否HEVC);看门狗每1.5s查居中视频时间不前进连续2次则跳过(不要求playing,抓Cannot Open/无权限黑屏)"
}
