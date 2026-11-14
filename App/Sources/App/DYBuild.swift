import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v131"
    static let changes = "v131: 去水印——选链照抄 myDV resolveFinalPlayUrl(auto)+selectBestPlayUrl:候选改 play_addr(f1/f9,无水印播放版)优先,f8(download_addr水印版,路径/video/cn/mps/logo/实锤)降为兜底;候选内四级优先级(签名douyinvod直链→/aweme/v1/play→signature=→最后一个)原样;旧v58顺序8→1→9踩了download_addr是水印根因;双链/age/repair机制不动"
}
