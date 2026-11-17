import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v202"
    static let changes = "v202: 修app图标-真正根因(axiom-tvos技能+Apple BrandAssetsType文档+react-native-vanilla模板三方交叉)。旧brandassets的Contents.json从项目第一天就是错的:对象式assets+裸PNG+无role/size,actool根本不认是合法brandassets集合→None of the input catalogs contained a matching→图标永不编译(记忆里的Assets.car gap就是它)。正确格式=assets数组+每条size/idiom/filename/role(primary-app-icon/top-shelf-image/top-shelf-image-wide)+filename指向.imagestack/.imageset子文件夹(图标是分层imagestack,顶架是imageset)。修:整目录重建为模板结构'App Icon & Top Shelf Image.brandassets'(tvOS默认查找名免设置,react-native-vanilla逐字节照抄)+AppStore图标imagestack(1280×768)+主屏图标imagestack(400×240)+顶架imageset两张(1920×720/2320×720),全单Front层平铺图标,删ASSETCATALOG设置(v199/v200实锤默认名匹配)。含v195启动加载视频过渡"
}
