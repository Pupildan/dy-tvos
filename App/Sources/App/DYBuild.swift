import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v111"
    static let changes = "v111: 治黑屏有声——player.status KVO补.failed分支(Cannot Open/HEVC解不出),预处理无感跳过:失败且是当前居中则驱逐坏player并advance到下一个,不停在黑屏"
}
