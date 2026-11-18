import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v213"
    static let changes = "v213: 直播弹幕WS + KSMEPlayer解流失败重试 + 封面占位。①直播弹幕(抖音第二版,数据照反编译myDV kq2/bp4/s30/x04/jq2,渲染沿用本项目思路,展现底部纵向聊天列表抖音样式): DYLiveDanmakuSocket(URLSessionWebSocketTask, wss webcast3-ws-web-lq+getMSSDKSignature签名+join hb帧+10s心跳+ack+重连5次)+DYLiveProto(手写protobuf PushFrame/Response/WebcastChatMessage解+hb/ack编+gzip解压Compression)+DYLiveChatOverlay(底部纵向@昵称:内容堆叠,纯展示焦点隔离)+DYSigner.msSign(调sign.js getMSSDKSignature)。匿名可连(user_unique_id用ttwid,探针live_danmaku_probe.js端到端验证收到真实WebcastChatMessage)。②KSMEPlayer解流失败(avformat can't open input,个别房CDN抖动/死房)重试1次同URL再advance跳房(handleKSFailure,ksFailureHandling闩防重入)。③封面占位(用户补充): 进房先显示DYLiveRoom.coverUrl,bufferFinished首帧淡出,coverLoadToken防切房竞态。铁律只有直播动,VOD弹幕/main feed/loading不碰"
}
