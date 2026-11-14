import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v127"
    static let changes = "v127: 稳定基线=v121代码(跳多页/声画/冻屏已修)+v122播放时现选新鲜URL;剥离v123-v126反复横跳的看门狗/视频轨检测实验,给一个确定的可靠版本"
}
