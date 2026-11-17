import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v186"
    static let changes = "v186: 修直播流屏三真机bug(日志实锤)。①上下键切不了房=直播屏无可聚焦元素(PlayerCell canBecomeFocused=false)遥控键没锚点→加DYLiveFocusCollectionView(canBecomeFocused=true)+preferredFocusEnvironments指向它+viewDidLayoutSubviews updateFocusIfNeeded,遥控上下键进pressesBegan切房;删右上角返回按钮(抢焦点)。②直播间没画面只有声音=createPlayer后AVPlayerItem.status异步才readyToPlay,但只updatePlaybackStates一次那时未ready卡封面→加KVO readyObservers(status→ready时补play,照VOD PlayerManager),驱逐时invalidate清理。③抖音视频还在后头放声音=进直播没暂停主feed→PlayerManager加pauseAll+RootView onChange(isLiveOpen)暂停。退出直播靠scrollTo恢复居中播放"
}
