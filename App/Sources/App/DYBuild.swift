import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v109"
    static let changes = "v109: 治跳号——按键精确±1(直接engine.next/prev),scrollTo用setIndex(删for{next()}跳号循环),engine.index唯一真相源;补seek/togglePlayPause/PlayerCell.currentTime/seek/isPlaying"
}
