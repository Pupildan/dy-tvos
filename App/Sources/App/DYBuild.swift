import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v189"
    static let changes = "v189: 修 v188 CI 编译错 tvOS上AVPlayerViewController.view是UIView?(iOS非可选)必须guard解包。其余同v188: 直播黑屏换LivePlayerCell内嵌AVPlayerViewController(标准组件自己render出画面,绕开手动AVPlayerLayer连败v186/v187两轮的泥潭),保留纵向分页/滑动切房/遥控上下键/游标翻页/池窗口/HLS"
}
