import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v183"
    static let changes = "v183: 直播功能第一版(匿名拉流播放,照抄myDV u11.java:1628-1695+x04.java:327-333+DataModelKt)。开发机探针live_probe.js实锤live.douyin.com不撞作品墙: feed status_code=0返回20真直播间, enter返回hls_pull_url_map(FULL_HD1/HD1/SD2/SD1)真HLS URL .m3u8可达(HEAD 200 application/x-mpegurl), 与现有feed/弹幕/评论同款a_bogus签名+匿名ttwid即可。新增DYLiveClient(fetchLiveFeed/enterRoom/bestHlsUrl按DataModelKt优先级选清晰度)+DYLiveUI(DYLiveBrowseScreen网格+DYLivePlayerScreen AVPlayer播HLS复用PlayerLayerView单房间独立不进PlayerManager池)+设置面板直播占位行转真入口selectLive(事务分离0.4s防焦点异常)+RootView挂载isLiveOpen zIndex13。第一版无弹幕(WebSocket getMSSDKSignature+protobuf解码留第二版)"
}
