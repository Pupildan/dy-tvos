import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v149"
    static let changes = "v149: ①评论闪退真根因修复:ensureTTWID 回调在 danmaku 队列内联执行,DYCommentClient 在同队列调 ttwidValue(queue.sync)自等待死锁→主线程跟着卡死被杀;回调改跳主线程;②两倍速改触摸板悬停1s触发(手指放触摸区不动,与滑动同区域,松开恢复;撤销确认键长按);③快捷面板真·底部居中(RootView ZStack leading对齐致面板贴左,补 maxWidth infinity)+标准液态玻璃去黑tint透出视频+评论屏黑幕减淡;④弹幕:顶部6行/禁止重叠/降速280;⑤右轨图标回落40pt/62px/头像80"
}
