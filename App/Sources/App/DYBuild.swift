import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v171"
    static let changes = "v171: 修v170真机两连——①点作品播的是别的视频(真根因=DYWorksJump同步触发时merge的insertItems还没跑,contentSize旧,scrollTo的targetY被maxOffset钳到旧底部;改jumpToWorksIndex轮询等item就绪再滚) ②作者页滑动穿透切视频(handlePan没护栏isProfileOpen/isCommentOpen;滑动改交焦点引擎移动网格焦点,pressesBegan焦点屏打开时也全放行焦点引擎)"
}
