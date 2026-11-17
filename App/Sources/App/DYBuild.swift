import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v198"
    static let changes = "v198: 修app图标不显示。根因(v197 ipa铁证)=tvOS brandassets格式(AppIcon.brandassets+idiom tv)actool编译出空结果——构建日志compilation-results块全空,ipa里无Assets.car、Info.plist无任何图标键(CFBundleIcons/AppIcon全False)。v195删top-shelf槽位/v196/v197都没治本。修=换标准AppIcon.appiconset(用户拍板):PIL把icon-large(1280×768)居中裁方+缩1024×1024生成icon-1024.png(抖音音符logo居中未切),新建AppIcon.appiconset/Contents.json(idiom tv/platform tvos/size 1024x1024),删整个AppIcon.brandassets旧目录。ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon指向不变。含v195启动加载视频过渡+首帧淡化"
}
