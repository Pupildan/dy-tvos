import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v204"
    static let changes = "v204: 直播黑屏-设备端终极诊断。开发机探针ts_debug.js实锤: 6房间×4清晰度全是H.264+AAC(HEVC假设证伪), 全部嵌套清单(L1指向L2 m3u8防盗链包装, livehwc4/100ycdn域), TS层100%对齐。编码假设排除后不再盲猜——加AVPlayerItem自带诊断: errorLog(底层错误码)/accessLog(传输字节)/presentationSize(视频解码出来才有值)/isReadyForDisplay/轨道数, play后3s+8s各dump一次LIVE DIAG行, 让AVPlayer自己说黑屏原因"
}
