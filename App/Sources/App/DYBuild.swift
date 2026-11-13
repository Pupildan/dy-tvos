import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v121"
    static let changes = "v121: 删.failed→advance自动跳过(跳多页+声画不同步根源)——failed保持封面不play不跳,等用户手动按↓;清skipFailed/onSkipFailed/failedIndices死代码"
}
