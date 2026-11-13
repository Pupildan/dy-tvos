import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v106"
    static let changes = "v106: PlayerManager上限3池(current±1)+距离驱逐(replaceCurrentItem(nil)回收解码器)根治解码器耗尽黑屏;Cell纯粹化willDisplay申请绑定;未就绪封面兜底绝不强行play"
}
