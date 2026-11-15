import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v179"
    static let changes = "v179: ①撤销v178真导航(20:14:20真机实锤:导航同秒用旧document的hooked=1判ready并fire,新页面次秒才补装hook→128作品作者一条都没截到;回到单一持久首页会话,不中途导航) ②翻页参数按myDV u11:3680对齐(need_time_list首页1翻页0——v178从首页模板复制时漏改成0) ③翻页URL改字符串级替换:不做percent重编码、删全部会话绑定参数(verifyFp/fp/msToken/a_bogus/uifid)交页面包装器重签、绝对URL还原成相对路径与首屏同构 ④软拒按3种变体重试(标准/换max_cursor游标值/换cursor参数键),全拒停发自拼但不判死hasMore ⑤XHR签名通道保留(v178真机NATIVE POST URL打全页面加的a_bogus/msToken/verifyFp,首屏有效)"
}
