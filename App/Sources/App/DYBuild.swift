import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v130"
    static let changes = "v130: 冷启动首帧提速+坏链快速恢复——①冷启动收敛:首个prepare只装居中条且直接走重定向直链(省掉静态直链4s空等+repair重建来回,v129实锤首帧11s→预期6s),邻居等居中ready再补装载(避免启动3个并发TLS握手互拖,v129 idx=1 TLS error实锤);②idle看门狗阈值4s→2s(repair实测1-2s恢复,静态直链打不开少等2s);UI美化(spinner等)按用户决定后期统一做"
}
