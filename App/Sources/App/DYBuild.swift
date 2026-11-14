import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v128"
    static let changes = "v128: 治残余黑屏三靶点(改动集中acquire/KVO/选链,不碰滚动/池路径)——①真新鲜URL:静态直链>90s改用/aweme/v1/play重定向(服务器现场302签名;v122旧resolveFreshURL被日志证伪381次fallback从未生效);②ready后查currentItem.tracks(.video)空轨0.6s复查→跳过(治黑屏无声);③isReadyForDisplay看门狗:有播放无首帧2s→先换源重建后跳(治黑屏有声,v123停滞看门狗盲区);护栏:只跳居中+连续3次停手;/stat升级计数器+事件环一次curl看全"
}
