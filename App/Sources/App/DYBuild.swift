import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v173"
    static let changes = "v173: ①点播改单条插入(用户否掉插整段=必须刷完所有作者作品才回推荐流;insertSingleWork=选中作品插当前播放位下一格,看完down一下就回feed、up回已看,随时退出) ②合集提速(真机反馈等很久;①复用活的作者页会话零加载直取 ②新会话interactive+1.5s即fetch不等challenge complete ③profile会话收摊15/25s→25/30s扩大复用窗口)"
}
