import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v136"
    static let changes = "v136: ①源切换真机验收通过(web ready x10/itemErr 0,18分钟长视频弹幕652条);②面板3s无操作自动隐藏(焦点移动/按键刷新计时);③弹幕区域回退v133行为(删v134 aspectFit内切,有bug待后修);④面板焦点样式:去灰底→焦点行白色描边+1.05缩放弹簧动画(@FocusState)"
}
