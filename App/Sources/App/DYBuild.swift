import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v116"
    static let changes = "v116: 基线还原——代码回退到v108(每Cell独占player+增量插入),剥离v109-v115实验代码(skip/advance/failedIndices/prepare窗口/删scroll委托);用于焦点实验的干净基线"
}
