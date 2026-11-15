import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v158"
    static let changes = "v158: ①资料接口回归修复:v157新增的浏览器一致性头(sec-ch-ua等)与URLSession指纹自相矛盾触发风控致资料屏200空——回退v153验证过的最小头配方,mssdk真msToken撤出主流程(真机MISS且无益);②触摸倍速按用户提供的方案实现:LongPress挂collectionView容器,minimumPressDuration=0.8+allowableMovement=10紧容差(超10px=滑动意图长按立即失败交还滑动,天然互斥)+cancelsTouchesInView=false+shouldRequireFailureOf失败排序;③确认键长按0.6s两倍速保留(双通道并存);④长按倍速中漂移不切视频"
}
