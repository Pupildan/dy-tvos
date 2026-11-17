import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v208"
    static let changes = "v208: 直播黑屏-照myDV实锤路径重写播放链。agent深挖反编译实锤: ①myDV live播的是FLV(extractMainLiveUrls flv在前index0走FlvExtractor), 不是HLS ②live请求无任何自定义头(OkHttpDataSource裸client, fo5头表仅VOD用) ③SDK路径优先于hls_pull_url_map。结合探针: HLS=TS媒体清单+嵌套L1→L2链式结构(非标准HLS, hls.js递归解析但AVPlayer行为不可控)。修: ①play前resolvePlaylist剥嵌套(L1片段行是m3u8→改播L2真TS清单) ②裸AVURLAsset去headers(对齐myDV裸client) ③playerVC.player=sharedPlayer保留(v207) ④DIAG日志保留。liveHeaders()留档不用"
}
