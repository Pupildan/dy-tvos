import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v162"
    static let changes = "v162: 资料获取稳定化(真机日志实锤WebView引导成功种下__ac_signature/s_v_web_id信任cookie,但连发限流致资料时好时坏)——①按作者缓存10分钟;②请求节流≥1.5s;③空响应自动重试一次;④作品探测每会话每作者一次;⑤资料屏失败态提示;作品列表仍200空(odin_tt等HttpOnly cookie JS不可见,继续观察)"
}
