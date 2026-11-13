import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v115"
    static let changes = "v115: 治一次按键跳多页——删scrollViewDidEnd两委托(动画中途centeredIndex反推索引致正反馈),advance/rewind直接engine.next/prev精确±1,scrollTo删for{next()}对齐循环;索引唯一来源=按键驱动引擎"
}
