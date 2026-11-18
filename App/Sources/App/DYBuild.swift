import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v216"
    static let changes = "v216: 直播弹幕渲染诊断(采集已确认通-日志采到32条真实聊天@昵称:内容, 但刷一堆房左下角一个都没显示)。数据通→渲染bug, 加临时诊断定位: chatOverlay.append时打 overlayFrame(在superview里的x/y/w/h)+rows行数+hidden+alpha+superview类型, 确认overlay在屏内/frame非0/行数累积/没被遮挡。怀疑方向: overlay自动布局塌缩(底部对齐+height lessThan 0.45,空时stack高0)/z序被挡/frame在屏外。采集链(v215已验证通:WS连接/心跳/gzip/protobuf/WebcastChatMessage解码全好)不动"
}
