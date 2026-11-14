import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v150"
    static let changes = "v150: ①弹幕空窗循环治理:发射器canShoot门控(被轨道拒不标记,腾出即补射)+轨道卡死10s自愈强制清轨+DMSYNC每4s诊断日志;②弹幕行距加大(轨道高34→50);③触摸悬停倍速加固:0.6s触发/漂移容限140/began必留日志+▶▶2x角标;④主页合集占位toast反馈(探针实锤:web作品接口UIFID墙403+mobile /aweme/post/ 匿名一律空列表,作品列表需登录态)"
}
