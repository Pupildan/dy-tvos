import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v215"
    static let changes = "v215: 直播弹幕采集诊断(铁律:先采到数据才真机验证渲染)。v214真机: OPENED(join sent)成功但11s内服务端0消息→连接被heartbeatDuration=10超时关闭(receive not connected)。两处采集诊断+心跳修复: ①心跳改DispatchQueue递归(原Timer在send完成回调后台线程创建+RunLoop.main.add跨线程可能不触发→服务端超时关连接), 加hb sent日志确认心跳真发出 ②打完整wss url(跟探针live_danmaku_probe.js逐参对比) ③handleBinary打收到的每条message method+chat内容(确认服务端推没推/推了什么)。目标=日志看到采到弹幕数据, 渲染验证往后放"
}
