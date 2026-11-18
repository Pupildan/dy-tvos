import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v217"
    static let changes = "v217: 修直播弹幕渲染塌缩(v216诊断实锤)。v216诊断: chatOverlay.append rows=1 overlayFrame=(24,959,1872,2)/rows=2 (24,954,1872,10)——宽度1872正常/位置底部/没遮挡/alpha=1, 但overlay高度塌缩到2-10px(每行~8px, 正常该~50px)=聊天行被压成一条线肉眼看不见。根因=ChatRow高度靠label内在内容尺寸驱动, 但overlay height<=0.45(只上限无下限)+stack top>=top让布局塌缩到最小, label被压缩。修=ChatRow加显式高度约束52px(52-4padding=48px容fontSize26单行)+label numberOfLines=1。采集链(v215已验证:WS/心跳/gzip/protobuf/WebcastChatMessage解码全好,采到32条真实聊天)不动"
}
