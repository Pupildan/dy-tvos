import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v209"
    static let changes = "v209: 直播黑屏-修诊断假阴性+修-16832卡顿。真机v208日志复盘实锤两病灶: ①rfd诊断假阴性=playerVC.view根layer是普通容器不是AVPlayerLayer, 旧代码 view?.layer as? AVPlayerLayer 永远cast失败→rfd恒0(49次全0), 从没量到真东西; 改=递归sublayers找真AVPlayerLayer+dump渲染树frame。②-16832 stall danger(11次)=单player replaceCurrentItem默认从直播边缘开播, 等item ready那几秒直播已往前走→卡在清单末端反复重启→ps=0x0不解出视频(35/49房); 改=item ready后从边缘往回seek 8s(2个target duration)再播。复用v207 playerVC.player赋值+v208剥嵌套/裸asset"
}
