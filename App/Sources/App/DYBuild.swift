import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v160"
    static let changes = "v160: 作品/合集解锁路径落地(用户拍板隐形WebView引导)——v159真机日志实锤URLSession也被jsvmp挑战页拦(challenge=1),信任cookie(s_v_web_id/odin_tt/uifid)只能由挑战页JS种下;新增DYWebViewBootstrap:1x1离屏WebView从不挂视图层级(铁律边界:非UI仅引导,同扫码登录路线),加载抖音首页让挑战JS自动算签名种cookie,15s兜底+didFinish+2s/+6s收割进DYProfileClient罐;D0身份参数(verifyFp/fp/webid)自动激活;资料屏链路=WebView引导→首页跳链→UIFID_TEMP→profile/works"
}
