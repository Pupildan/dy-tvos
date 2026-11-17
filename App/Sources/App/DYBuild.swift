import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v203"
    static let changes = "v203: 修图标-最后两个actool document error(v202 CI日志实锤,此前所有轮次没暴露因为旧格式错误actool根本没走到内容校验)。①The last image stack layer with content Front must be a fully opaque bitmap(alpha 139/84)→图标PNG是RGBA带透明,压平成RGB不透明(over black,视觉不变);②The image stack must have at least 2 layers→单层Front不合法,每stack加Back层(纯黑不透明)成Front+Back双层。顶架图也压平消warning(必须fully opaque)。⚠️坑:actool document error不fail CI构建(CI绿但图标内容被丢弃),验证必须拆ipa+看CI日志actool document errors段。含v195加载视频过渡+v202模板格式"
}
