import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v175"
    static let changes = "v175: ①闪退修复(回到推荐removeWorksSegment段内key重映射撞key/负数→Dictionary fatal;先剔除段区间) ②分页对齐myDV反编译u11:3680-3703(aweme/post完整14参数,need_time_list首页1翻页0,version_code290100;v174缺6参数→第二页200空len17) ③翻页游标改响应cursor(UserWorksResponse.getCursor)非max_cursor ④合集权威化(myDV手机端s13从不填MixInfo,f14f6无依据真机错位→aweme/detail→mix_info.mix_id再打mix/aweme;集数用mix_info.statis.current_episode,nx3同款) ⑤提速(双发去重+就绪每tick连发2条+删RootView重复fetch)"
}
