import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v177"
    static let changes = "v177: ①作品翻页(真机空响应body=status_code:0验签软拒实锤;根因=_dytag是塞进query的服务端不认识参数→a_bogus基于完整query算,页面签名包装只签白名单→参数集不一致;标记全改URL fragment(#postcap等,浏览器不发fragment不参与签名,逐字节对齐myDV参数),hook的u保留#tag供分发;页面包装后带签名请求的响应也纳入按id去重累积双通道) ②快捷栏焦点选中只留液态玻璃描边(白渐变+微光),去掉选中背景glass tint/ultraThinMaterial填充"
}
