import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v184"
    static let changes = "v184: 直播改成全屏纵向分页刷直播间+无限加载(真机反馈:网格展示不对+只能拿一批~20个房间)。开发机探针live_feed_paging_probe.js实锤翻页游标=响应extra.max_time(毫秒时间戳)+extra.has_more,逐页前进,链式4页累积36去重房间→无限刷成立。DYLiveClient加游标翻页(loadMore/feedMaxTime/feedHasMore/seenWebRids跨页去重,滚到倒数5个自动翻页)。DYLiveUI整体重写:删网格DYLiveBrowseScreen→DYLiveFeedScreen+DYLiveFeedViewController(照抄NativePlayerView的UICollectionView垂直分页+pan手势护栏+snap+上下遥控切房+池窗口[idx-1,idx+1]驱逐,数据走DYLiveClient游标翻页,HLS单房间池enter resolve后建AVPlayer)。PlayerCell加configureLive(隐藏弹幕层+右轨,观看数拼createTimeText渲染@主播·X观看)+setRailVisible。复用PlayerLayerView/AvatarLoader/DYVideoInfo(nickname=主播,desc=标题)。仍无弹幕(WebSocket留后续)"
}
