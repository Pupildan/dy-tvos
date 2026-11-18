import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v218"
    static let changes = "v218: 直播弹幕不显示-彻底重写chatOverlay为frame布局(一次性排除所有不显示可能)。v217仅改行高52px仍不显示, 用户要求一次性排除所有可能。系统排查6类可能(overlay高度autolayout塌缩/行高塌缩/z序遮挡/frame屏外/hidden-alpha/连接掉线清空), 根因=overlay用autolayout(height<=0.45只上限+stack top>=top)允许塌缩到2-10px。彻底重写DYLiveChatOverlay为frame布局: 去掉UIStackView+autolayout, chatRows数组+layoutSubviews按底部向上定位每行(固定52px行高+6px间距), overlay本身固定frame(左下角x24/宽屏0.6/高344/底距屏底140), 尺寸位置完全确定消灭autolayout塌缩整类问题。加append诊断(打每行frame+overlay frame+n+hidden+superview)。采集链(v215验证通)不动, 铁律只动直播"
}
