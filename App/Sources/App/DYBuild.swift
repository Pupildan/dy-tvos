import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v199"
    static let changes = "v199: 修app图标不显示(v197/v198 ipa铁证无Assets.car、Info.plist无图标键)。CI日志两条warning锁定根因:①标准appiconset格式tvOS不认(has an unassigned child)②ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon让actool强找brandassets集合但找不到(None of the input catalogs contained a matching App Icon & Top Shelf Image brand assets collection named AppIcon)。修:AppIcon.brandassets只留尺寸对的app-large(1280×768)+app-small(400×240)删掉尺寸错的top-shelf槽位(1920×720塞正方形槽位拖垮整个catalog编译),删ASSETCATALOG行让actool自动识别唯一brandassets集合产图标。含v195启动加载视频过渡+首帧淡化"
}
