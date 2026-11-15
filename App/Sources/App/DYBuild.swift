import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v157"
    static let changes = "v157: 主页作品接口继续深挖——①补齐myDV每请求静态头n(u11:80:sec-ch-ua/sec-fetch-*/priority/cache-control全套浏览器一致性头,探针发现此前缺失);②真msToken(mssdk/web/r/token u11:729常量程序化提取照抄DYMsSdk.swift);③aweme/detail接口探针已通(视频详情真实数据)后续合集可用;作品列表真机试探带全链(真msToken+全套头+uifid),日志WORKS行定论"
}
