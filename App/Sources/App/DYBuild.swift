import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v155"
    static let changes = "v155: 撤销v154,保留触摸悬停两倍速(用户实测v153共存委托版可触发,长按确认键版本作废不装)——NativePlayerView 恢复 v153 状态(LongPress+pan小位移+共存委托+互斥判定);其余同v153(主页屏真机已通/模糊背景已撤/弹幕20s窗口已验)"
}
