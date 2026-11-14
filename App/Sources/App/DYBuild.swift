import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v134"
    static let changes = "v134: 弹幕样式按用户要求修正——①去白底(DanmakuAsyncLayer 在 isOpaque=true 时主动填白是白底来源,DanmakuTextCell 显式 isOpaque=false);②去描边(纯白字,弹幕数据无颜色字段,默认色即白);③弹幕区域限定视频aspectFit内切矩形(手机竖版源在16:9屏是居中窄条,弹幕只飘画面不飘黑边,presentationSize ready后校准+滚屏时长按区域宽计算)"
}
