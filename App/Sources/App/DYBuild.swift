import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v214"
    static let changes = "v214: 修v213两个真机问题。①左下角没出弹幕: 真机日志 receive fail=Socket is not connected——根因=resume后WS握手未完成就立即receive/send join(对比探针Node ws是等open事件后才发join)。修=sendJoinWhenConnected: resume后先发join帧, 用其send完成回调作已连接信号(成功→起心跳+receive循环; not connected→延迟1s重试join等握手)。②封面放大显示: 旧coverImageView用scaleAspectFill会裁切放大。改主流做法=coverView容器内两层: coverBgImageView(同封面CIGaussianBlur高斯模糊铺满)+coverFgImageView(scaleAspectFit原比例居中不裁切), blurredImage(radius:25) helper。v213其余(弹幕WS receive循环/protobuf/gzip/解流失败重试/焦点隔离)保留"
}
