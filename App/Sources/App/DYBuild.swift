import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v195"
    static let changes = "v195: 启动加载视频过渡+修图标。①图标不显示根因=icon-topshelf-square.png尺寸错(1920×720,槽位要1280×1280正方形)→actool编译整个Assets.xcassets失败连app icon都没出;且project.yml:40引用不存在的AccentColor colorset。修=删top-shelf两槽位(只留app-large/small-icon,尺寸对)+删AccentColor行。②启动黑屏→加LaunchVideoOverlay(控制器级AVPlayerViewController播App/Resources/loading.mp4,静音+循环,照v189/v193出画面方案),RootView顶层zIndex30遮启动黑屏;NativePlayerView watchTick首帧isReadyForDisplay置PlaybackEngine.firstFrameReady,RootView onChange交叉淡化0.6s掉overlay露出主feed(过渡自然不突兀)。视频打包App/Resources/loading.mp4(8.6MB,Bundle.main访问照DYSigner同款)"
}
