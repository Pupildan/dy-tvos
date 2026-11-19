import Foundation

/// 版本号唯一来源 —— 复用飞牛流水线约定。
/// 每次交付 version 必须 +1，禁止重复版本号（一个版本号 = 一个唯一构建产物）。
/// 用户可在设置面板核对当前版本。
enum DYBuild {
    static let version = "v219"
    static let changes = "v219: 直播弹幕视频区自适应定位 + 去@ + 表情包图片(三块一次性)。①视频区自适应定位(核心): 竖屏直播aspectFit居中留黑边, 弹幕+标题按全屏定位落在黑边。加videoRect=AVMakeRect(aspectRatio:naturalSize, insideRect:ksContainer.bounds), naturalSize从ksCoordinator.playerLayer?.player.naturalSize取(竖屏1080x1920居中窄条/横屏满宽自动适配), bufferFinished+viewDidLayoutSubviews时updateVideoRect; chatOverlay+LivePlayerCell标题按videoRect左下角定位。②去@: ChatRow.configure去掉@(用户要求)。③表情包图片: /aweme/v1/web/emoji/list(探针验证214个emoji shortcode→图片URL)→DYLiveEmojiClient(拉list+下载图片+NSCache), ChatRow.configure解析content里[捂脸]shortcode→NSTextAttachment内联图片, 去掉@后昵称：内容混排表情。铁律只动直播, VOD弹幕/main feed/loading不碰"
}
