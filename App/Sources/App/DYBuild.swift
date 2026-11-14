import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v142"
    static let changes = "v142: 弹幕空窗+扎堆修复——数据侧已证实无空窗(79s视频1212条30s桶直方图连续),根因=峰值密度41条/s远超发射吞吐,同秒全部抢23轨大部分被丢;修复①发射器每tick限量6条(24/s)平滑排队;②isOverlap=true允许同轨重叠(PC版同密度观感);峰值期积压在40s grace内消化"
}
