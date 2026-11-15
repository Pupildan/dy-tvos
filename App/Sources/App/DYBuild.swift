import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v154"
    static let changes = "v154: ①两倍速定版=长按确认键0.6s触发松开恢复(短按仍呼出快捷面板)——触摸悬停全部逻辑删干净(LongPress手势/pan悬停/共存委托,v146-v153真机始终不可靠,用户拍板弃用);②主页屏已真机验证通(profile接口 fans/works 真实数据);作品列表真机也是200空(URLSession TLS指纹理论证伪),服务端拒绝更深待另挖路径"
}
