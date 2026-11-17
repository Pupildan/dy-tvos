import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v201"
    static let changes = "v201: 修app图标不显示-完整根因链(v195-v200六轮)。v200 CI日志铁证:删ASSETCATALOG后tvOS构建系统回退默认图标名'App Icon & Top Shelf Image'(actool参数--app-icon App\\ Icon\\ \\&\\ Top\\ Shelf\\ Image),与文件夹名AppIcon.brandassets(集合名=AppIcon)不匹配→None of the input catalogs contained a matching→整个brandassets不编译→无Assets.car。且v197复盘:名字匹配但只有large+small两槽位也静默不产出=tvOS brandassets集合必须四槽位完整(App Icon & Top Shelf Image类型)。修:①恢复ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon(匹配文件夹名)②catalog四槽位完整(已v200做到)③尺寸全对(square已修1280×1280,logo居中未切,PIL从1920×720源图按logo位置裁)。名字匹配+集合完整+尺寸正确三条件齐"
}
