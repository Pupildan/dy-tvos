import SwiftUI
import UIKit
import AVFoundation
import AVKit
import KSPlayer

// MARK: - 直播流屏（v212 播放内核 AVPlayer→KSPlayer/KSMEPlayer。铁律：只有直播内核能换，VOD/主feed/loading 不动）
// v185→v211 十几轮实锤：AVPlayer 对抖音直播 HLS 卡 -16832 追边 stall 永远解不出首帧（ffprobe 证实流/渲染层都好）。
// 换 KSMEPlayer（FFmpeg 软解，独立 HLS demuxer）绕开 AVPlayer 整套 live-edge 逻辑。

/// SwiftUI 包装：直播纵向分页流（全屏）。设置面板「直播」进入；Menu 关闭回播放。
struct DYLiveFeedScreen: View {
    @ObservedObject var model = DYQuickPanelModel.shared

    var body: some View {
        DYLiveFeedView()
            .ignoresSafeArea()
            .onExitCommand { model.isLiveOpen = false }
            .transition(.opacity)
    }
}

struct DYLiveFeedView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DYLiveFeedViewController {
        DYLiveFeedViewController()
    }
    func updateUIViewController(_ uiViewController: DYLiveFeedViewController, context: Context) {}
}

/// 可聚焦 collectionView：PlayerCell `canBecomeFocused=false`（照 VOD），但直播屏需要遥控上下键锚点
/// → 让 collectionView 自己可聚焦。聚焦后遥控上下键走 live VC 的 pressesBegan 切房。
final class DYLiveFocusCollectionView: UICollectionView {
    override var canBecomeFocused: Bool { true }
}

/// 直播单房间 cell（v193）：**不渲染视频**（视频由控制器级 AVPlayerViewController 渲染，浮在 collection view 下）。
/// cell 只负责标题/观看数 overlay（透明背景，让下面的视频透出）。
/// v192 黑屏根因：把出画面的 AVPlayerViewController 换成手动 PlayerLayerView(AVPlayerLayer)——v186/v187 黑屏老路。
/// v189 出画面靠 AVPlayerViewController。正确组合 = AVPlayerViewController 管渲染 + v192 asset header。
final class LivePlayerCell: UICollectionViewCell {
    private let nicknameLabel = UILabel()
    private let descLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear   // 透明：让控制器级视频层透出
        // 左上信息区（v220：移到视频区左上角 + 减小字体，不影响观看）
        nicknameLabel.font = .boldSystemFont(ofSize: 26)
        nicknameLabel.textColor = .white
        nicknameLabel.shadowColor = .black
        nicknameLabel.shadowOffset = CGSize(width: 1, height: 1)
        descLabel.font = .systemFont(ofSize: 22, weight: .medium)
        descLabel.textColor = .white
        descLabel.shadowColor = .black
        descLabel.shadowOffset = CGSize(width: 1, height: 1)
        descLabel.numberOfLines = 2
        contentView.addSubview(nicknameLabel)
        contentView.addSubview(descLabel)
        isUserInteractionEnabled = false   // 照 VOD cell：排除出焦点/触摸，滑动不被干扰
    }
    /// v219：视频显示区域（VC 算好传入）——标题定位到视频区左下角
    var videoRect: CGRect = .zero
    required init?(coder: NSCoder) { fatalError() }
    override var canBecomeFocused: Bool { false }
    private static let textShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = UIColor.black
        s.shadowOffset = CGSize(width: 1, height: 1)
        s.shadowBlurRadius = 2
        return s
    }()
    override func layoutSubviews() {
        super.layoutSubviews()
        // v220：标题定位到视频区左上角（竖屏视频居中留黑边时，标题落在视频内上方；不影响观看）
        // videoRect 由 VC 算好传进来；为空/异常时回退到 cell bounds（旧行为）。
        let vr = videoRect.isEmpty ? contentView.bounds : videoRect
        let infoLeft: CGFloat = vr.minX + 24
        let infoTop: CGFloat = vr.minY + 24
        let infoW = vr.width - 48
        nicknameLabel.frame = CGRect(x: infoLeft, y: infoTop, width: infoW, height: 36)
        descLabel.frame = CGRect(x: infoLeft, y: infoTop + 36 + 4, width: infoW, height: 52)
    }

    /// 填标题/观看数（照 VOD applyInfo 同行排版：@主播 · X观看 / 标题）
    func configure(room: DYLiveRoom, viewerText: String) {
        let nick = room.ownerName.isEmpty ? "" : "@\(room.ownerName)"
        if nick.isEmpty && viewerText.isEmpty {
            nicknameLabel.attributedText = nil
        } else {
            let s = NSMutableAttributedString()
            if !nick.isEmpty {
                s.append(NSAttributedString(string: nick, attributes: [.font: UIFont.boldSystemFont(ofSize: 26), .foregroundColor: UIColor.white, .shadow: Self.textShadow]))
                if !viewerText.isEmpty { s.append(NSAttributedString(string: "  ·  ", attributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.white.withAlphaComponent(0.7), .shadow: Self.textShadow])) }
            }
            if !viewerText.isEmpty {
                s.append(NSAttributedString(string: viewerText, attributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.white.withAlphaComponent(0.75), .shadow: Self.textShadow]))
            }
            nicknameLabel.attributedText = s
        }
        descLabel.text = room.title.isEmpty ? nil : room.title
    }
}

/// 直播纵向分页控制器（v212 播放内核 AVPlayer→KSPlayer/KSMEPlayer，照 myDV 全局共享单 player 换 URL，非池）。
/// v189-v191 连败三轮根因=per-cell player 池（窗口驱逐+缓存）多 player 抢解码器 → 大部分黑屏。
/// v185→v211 AVPlayer 路径：渲染层/流/编码全好（ffprobe+渲染树实锤），唯独 AVPlayer 卡 -16832 追边 stall 解不出首帧。
/// v212 换 KSMEPlayer（FFmpeg 软解，独立 HLS demuxer）绕开 AVPlayer 整套 live-edge 逻辑。
/// 视频层浮在 collection view 下；cell 透明只显示标题/观看数 overlay；换房 makeView(新URL) 换流（分页/滑动动画不动）。
final class DYLiveFeedViewController: UIViewController {
    private var collectionView: UICollectionView!
    private var currentIndex = 0
    private var didInitialScroll = false

    /// KSPlayer 协调器（持 KSPlayerLayer，换房 makeView(新URL) 内部走 playerLayer.set(url:) 换流）
    /// ⚠️ Coordinator 是 @MainActor——在 viewDidLoad（主线程）里初始化，避免属性初始化器的 actor 隔离问题。
    private var ksCoordinator: KSVideoPlayer.Coordinator!
    /// 视频渲染容器（KSPlayer 的 player.view 加在这里面，浮在 collection view 下）
    private let ksContainer = UIView()
    private var ksViewAdded = false
    private var hlsCache: [String: String] = [:]       // webRid → 已 resolve 的 HLS URL
    private var resolving = Set<String>()              // webRid → enter 在飞去重
    private var playingWebRid = ""                     // 当前共享 player 正在放的房间
    private var lastKSPlayLogAt = TimeInterval(0)      // v212 onPlay 节流（0.1s 定时器驱动，不节流会刷爆日志）
    // v213：封面占位（首帧前盖住黑屏，bufferFinished 淡出）。主流做法=全屏模糊背景 + 原比例居中封面。
    private let coverView = UIView()                   // 封面容器（满屏）
    private let coverBgImageView = UIImageView()       // 模糊背景（同封面高斯模糊，铺满）
    private let coverFgImageView = UIImageView()       // 原比例封面（scaleAspectFit 居中，不裁切）
    private var coverLoadToken = 0                     // 防异步封面加载竞态（快速切房时旧加载回写）
    // v213：底部聊天列表 overlay（抖音样式）+ 弹幕 WS
    private var chatOverlay: DYLiveChatOverlay!
    private let danmakuSocket = DYLiveDanmakuSocket()
    // v213：KSMEPlayer 解流失败重试（avformat can't open input 等）
    private var currentPlayUrl = ""
    private var ksRetryUsed = false
    private var ksFailureHandling = false
    // v219：视频显示区域（aspectFit 后视频实际占的 rect，竖屏居中窄条/横屏满宽）——弹幕+标题按它定位
    private var videoRect: CGRect = .zero
    // v219：表情包图片（shortcode 含方括号 → UIImage），开直播屏时预加载
    private var emojiImages: [String: UIImage] = [:]
    // v221：弹幕是否已随画面 reveal——画面出首帧(bufferFinished)前隐藏弹幕，避免"画面没出弹幕先出"
    private var chatRevealed = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // 1) 视频渲染层（v212 KSPlayer/KSMEPlayer）——先锁 FFmpeg 软解，再建容器（视频 view 在 play() 里 makeView 后加进来）
        // ⚠️ 锁 KSMEPlayer 是换内核的真正价值：AVPlayer 卡 -16832 追边 stall，FFmpeg 有独立 HLS demuxer 绕开它。
        //    若落回 KSAVPlayer（KSPlayer 对 AVPlayer 的封装）= 换汤不换药还是同一个 stall。
        KSOptions.firstPlayerType = KSMEPlayer.self
        ksCoordinator = KSVideoPlayer.Coordinator()
        setupKSCallbacks()
        ksContainer.backgroundColor = .black
        ksContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ksContainer)
        NSLayoutConstraint.activate([
            ksContainer.topAnchor.constraint(equalTo: view.topAnchor),
            ksContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ksContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ksContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        // 1b) 封面占位层（v213：主流做法=全屏模糊背景 + 原比例居中封面）——z 序 ksContainer < cover < chat < collection
        coverView.backgroundColor = .black
        coverView.clipsToBounds = true
        coverView.isHidden = true
        coverView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(coverView)
        NSLayoutConstraint.activate([
            coverView.topAnchor.constraint(equalTo: view.topAnchor),
            coverView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            coverView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        // 模糊背景层（同封面高斯模糊后铺满，主流做法）
        coverBgImageView.contentMode = .scaleAspectFill
        coverBgImageView.clipsToBounds = true
        coverBgImageView.translatesAutoresizingMaskIntoConstraints = false
        coverView.addSubview(coverBgImageView)
        NSLayoutConstraint.activate([
            coverBgImageView.topAnchor.constraint(equalTo: coverView.topAnchor),
            coverBgImageView.bottomAnchor.constraint(equalTo: coverView.bottomAnchor),
            coverBgImageView.leadingAnchor.constraint(equalTo: coverView.leadingAnchor),
            coverBgImageView.trailingAnchor.constraint(equalTo: coverView.trailingAnchor),
        ])
        // 原比例前景层（scaleAspectFit 居中，不放大不裁切）
        coverFgImageView.contentMode = .scaleAspectFit
        coverFgImageView.clipsToBounds = true
        coverFgImageView.translatesAutoresizingMaskIntoConstraints = false
        coverView.addSubview(coverFgImageView)
        NSLayoutConstraint.activate([
            coverFgImageView.topAnchor.constraint(equalTo: coverView.topAnchor),
            coverFgImageView.bottomAnchor.constraint(equalTo: coverView.bottomAnchor),
            coverFgImageView.leadingAnchor.constraint(equalTo: coverView.leadingAnchor),
            coverFgImageView.trailingAnchor.constraint(equalTo: coverView.trailingAnchor),
        ])
        // 1c) 弹幕底部聊天列表 overlay（v217 frame 布局，固定尺寸/位置，彻底消灭 autolayout 塌缩）
        //     固定左下角：x=24，宽=屏宽*0.6，高=344（6 行*52 + 5*6 间距），底边距屏底 140。z 序在封面上、标题下。
        let chatW = UIScreen.main.bounds.width * 0.6
        let chatH: CGFloat = 344
        chatOverlay = DYLiveChatOverlay(frame: CGRect(
            x: 24,
            y: UIScreen.main.bounds.height - 140 - chatH,
            width: chatW,
            height: chatH))
        chatOverlay.isHidden = true   // v221：画面出首帧前隐藏弹幕（onChat 照常累积，reveal 后一并可见）
        view.addSubview(chatOverlay)
        // 弹幕 WS 回调：收到聊天 → 喂底部列表（带表情包图片内联渲染）
        danmakuSocket.onChat = { [weak self] msg in
            guard let self else { return }
            self.chatOverlay.append(nickname: msg.nickname, content: msg.content, emojiImages: self.emojiImages)
        }
        // v219：预加载表情包图片（[捂脸]→图片，供弹幕内联渲染）
        let ttwid = DYDanmakuClient.shared.ttwidValue
        DYLiveEmojiClient.shared.loadAll(ttwid: ttwid) { [weak self] images in
            self?.emojiImages = images
            DYLog.shared.log("LIVE emoji loaded count=\(images.count)")
        }
        // 2) collection view（透明，标题 overlay 浮在视频上）
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collectionView = DYLiveFocusCollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.register(LivePlayerCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.panGestureRecognizer.isEnabled = false   // 关原生滚动，手势接管（照 NativePlayerView）
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        setupGestures()
        loadFeed()
    }

    private func loadFeed() {
        DYLiveClient.shared.fetchLiveFeed { [weak self] fresh in
            guard let self else { return }
            guard !fresh.isEmpty else {
                DYLog.shared.event("LIVE feed empty on open")
                return
            }
            self.collectionView.reloadData()
            self.didInitialScroll = false
            self.view.setNeedsLayout()
        }
    }

    // MARK: 手势（照 NativePlayerView：关原生滚动 + pan 阈值 100 + 焦点屏护栏）
    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard DYQuickPanelModel.shared.isOpen == false, DYSettingsModel.shared.isOpen == false,
              DYQuickPanelModel.shared.isProfileOpen == false, DYQuickPanelModel.shared.isCommentOpen == false,
              DYQuickPanelModel.shared.isMixOpen == false else { return }
        let t = g.translation(in: view)
        guard abs(t.y) > 100 else { return }
        g.setTranslation(.zero, in: view)
        if t.y < 0 { advance() } else { rewind() }
        DYLog.shared.log("LIVEFEED swipe \(t.y < 0 ? "up" : "down") -> switch")
    }

    private func advance() { scrollTo(index: centeredIndex() + 1, animated: true) }
    private func rewind() { scrollTo(index: max(0, centeredIndex() - 1), animated: true) }

    private func scrollTo(index: Int, animated: Bool) {
        let count = DYLiveClient.shared.rooms.count
        guard count > 0, index >= 0, index < count else { return }
        let clamped = min(max(0, index), count - 1)
        let pageHeight = max(1, collectionView.bounds.height)
        let maxOffset = max(0, collectionView.contentSize.height - collectionView.bounds.height)
        let targetY = min(CGFloat(clamped) * pageHeight, maxOffset)
        collectionView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
        currentIndex = clamped
        if clamped >= count - 5 { loadMoreIfNeeded() }
        DYLog.shared.log("LIVEFEED scrollTo idx=\(clamped) y=\(targetY) items=\(count)")
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.35 : 0.05)) { [weak self] in
            self?.updatePlaybackStates(center: clamped)
        }
    }

    private func centeredIndex() -> Int {
        guard collectionView.bounds.height > 0 else { return currentIndex }
        let center = CGPoint(x: collectionView.bounds.midX, y: collectionView.bounds.midY)
        if let ip = collectionView.indexPathForItem(at: center) { return ip.item }
        return Int(round(collectionView.contentOffset.y / max(1, collectionView.bounds.height)))
    }

    /// 居中房间播放（单共享 player 换 URL）
    private func updatePlaybackStates(center index: Int) {
        let rooms = DYLiveClient.shared.rooms
        guard rooms.indices.contains(index), let room = rooms[index] as DYLiveRoom? else { return }
        playRoom(room)
    }

    /// 播房间：显示封面占位 + 连弹幕 WS → resolve HLS（缓存优先）→ KSPlayer 换 URL 播
    private func playRoom(_ room: DYLiveRoom) {
        if playingWebRid == room.webRid { return }   // 已在放同一房间
        // v213：新房间 → 重置解流失败重试 + 显示封面占位 + 连弹幕 WS
        ksRetryUsed = false
        showCover(for: room)
        connectDanmaku(room: room)
        if let hls = hlsCache[room.webRid] {
            play(url: hls, webRid: room.webRid)
            return
        }
        let feedHls = DYLiveClient.bestHlsUrl(room.hlsUrls)
        if !feedHls.isEmpty {
            hlsCache[room.webRid] = feedHls
            play(url: feedHls, webRid: room.webRid)
            return
        }
        guard !resolving.contains(room.webRid) else { return }
        resolving.insert(room.webRid)
        DYLog.shared.log("LIVEFEED resolve webRid=\(room.webRid)")
        DYLiveClient.shared.enterRoom(room.webRid) { [weak self] entered in
            guard let self else { return }
            self.resolving.remove(room.webRid)
            guard let entered else {
                DYLog.shared.event("LIVEFEED resolve fail webRid=\(room.webRid)")
                return
            }
            let hls = DYLiveClient.bestHlsUrl(entered.hlsUrls)
            guard !hls.isEmpty else {
                DYLog.shared.event("LIVEFEED resolve no-hls webRid=\(room.webRid)")
                return
            }
            self.hlsCache[room.webRid] = hls
            self.play(url: hls, webRid: room.webRid)
        }
    }

    /// v213：显示房间封面占位（异步加载，带 token 防快速切房竞态）
    private func showCover(for room: DYLiveRoom) {
        coverLoadToken += 1
        let token = coverLoadToken
        // 先清掉旧封面（显示黑屏），等新封面加载好再显示
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.coverLoadToken else { return }
            self.coverBgImageView.image = nil
            self.coverFgImageView.image = nil
            self.coverView.isHidden = true
        }
        guard !room.coverUrl.isEmpty, let url = URL(string: room.coverUrl) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = UIImage(data: data) else { return }
            // 主流做法：背景=同封面高斯模糊铺满；前景=原比例居中（不放大不裁切）
            let blurred = Self.blurredImage(img, radius: 25)
            DispatchQueue.main.async {
                guard let self, token == self.coverLoadToken else { return }
                self.coverBgImageView.image = blurred ?? img
                self.coverFgImageView.image = img
                self.coverView.isHidden = false
                DYLog.shared.log("LIVE cover shown webRid=\(room.webRid)")
            }
        }.resume()
    }

    /// v213：高斯模糊（封面背景用，CoreImage CIGaussianBlur）
    private static func blurredImage(_ image: UIImage, radius: CGFloat) -> UIImage? {
        guard let ci = CIImage(image: image) else { return nil }
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ci, forKey: kCIInputImageKey)
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        guard let out = filter?.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// v213：连直播弹幕 WS（roomId 从 enter 解析；userId/cookie 用匿名 ttwid，探针已验证）
    private func connectDanmaku(room: DYLiveRoom) {
        chatOverlay.clear()
        // v221：切房重新隐藏弹幕，等新房画面出首帧再 reveal
        chatRevealed = false
        chatOverlay.isHidden = true
        let ttwid = DYDanmakuClient.shared.ttwidValue
        danmakuSocket.connect(room: room, ttwid: ttwid)
    }

    /// KSPlayer 换流播房（v212）。makeView 幂等：同 URL 返回已有 view，URL 变了内部走 playerLayer.set(url:) 换流。
    /// 不再剥嵌套清单——KSMEPlayer 用 FFmpeg 自己的 HLS demuxer，不吃 AVPlayer 那套嵌套限制。
    private func play(url: String, webRid: String) {
        guard playingWebRid != webRid, let u = URL(string: url) else { return }
        playingWebRid = webRid
        currentPlayUrl = url
        ksFailureHandling = false   // 每次播放尝试重置失败处理闩（重试/新流都算新尝试）
        DYLog.shared.event("LIVEFEED play(KS) webRid=\(webRid) url=\(url.prefix(70))")
        // makeView 返回 KSPlayerLayer 的 player.view；首次加进 ksContainer 并锚满四边，之后复用同一 view
        let v = ksCoordinator.makeView(url: u, options: makeKSOptions())
        if !ksViewAdded {
            v.backgroundColor = .black
            v.translatesAutoresizingMaskIntoConstraints = false
            ksContainer.addSubview(v)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: ksContainer.topAnchor),
                v.bottomAnchor.constraint(equalTo: ksContainer.bottomAnchor),
                v.leadingAnchor.constraint(equalTo: ksContainer.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: ksContainer.trailingAnchor),
            ])
            ksViewAdded = true
        }
    }

    /// v212/v213：KSPlayer 状态回调。`.bufferFinished`=画面渲染中（淡出封面）；`.error`=解流失败（重试再跳房）。
    private func setupKSCallbacks() {
        ksCoordinator.onStateChanged = { [weak self] _, state in
            DYLog.shared.log("LIVE KS state=\(state.description) webRid=\(self?.playingWebRid ?? "-")")
            guard let self else { return }
            switch state {
            case .bufferFinished:
                // v219：首帧已渲染 → 重算视频显示区域（naturalSize 此时已知）+ 淡出封面占位
                self.updateVideoRect()
                // v221：画面出首帧了 → reveal 弹幕（此前隐藏但 onChat 照常累积，此刻一并淡入）
                if !self.chatRevealed {
                    self.chatRevealed = true
                    self.chatOverlay.alpha = 0
                    self.chatOverlay.isHidden = false
                    UIView.animate(withDuration: 0.3) { self.chatOverlay.alpha = 1 }
                    DYLog.shared.log("LIVE chat reveal webRid=\(self.playingWebRid)")
                }
                if !self.coverView.isHidden {
                    UIView.animate(withDuration: 0.35, animations: { self.coverView.alpha = 0 }) { _ in
                        self.coverView.isHidden = true
                        self.coverView.alpha = 1   // 复位 alpha 供下次切房
                    }
                }
            case .error:
                // v213：解流失败（avformat can't open input 等）→ 重试 1 次再跳下一房
                self.handleKSFailure()
            default:
                break
            }
        }
        ksCoordinator.onPlay = { [weak self] current, total in
            // onPlay 由 KSPlayerLayer 0.1s 定时器驱动（每秒 ~10 次）——节流到每 5s 记一条，否则刷爆日志。
            guard let self else { return }
            let now = Date().timeIntervalSince1970
            guard now - self.lastKSPlayLogAt >= 5.0 else { return }
            self.lastKSPlayLogAt = now
            DYLog.shared.log("LIVE KS onPlay cur=\(String(format: "%.1f", current)) total=\(String(format: "%.1f", total)) webRid=\(self.playingWebRid)")
        }
        ksCoordinator.onFinish = { [weak self] _, error in
            DYLog.shared.log("LIVE KS finish err=\(error?.localizedDescription ?? "-") webRid=\(self?.playingWebRid ?? "-")")
        }
    }

    /// v219：计算视频显示区域（aspectFit 后视频实际占的 rect）——弹幕/标题按它定位，竖屏居中窄条/横屏满宽自动适配。
    /// naturalSize 从 KSPlayer 取（ KSMEPlayer.naturalSize）；ksContainer 满屏，视频 aspectFit 居中留黑边。
    private func updateVideoRect() {
        let container = ksContainer.bounds
        guard container.width > 0, container.height > 0 else { return }
        let ns = ksCoordinator.playerLayer?.player.naturalSize ?? .zero
        guard ns.width > 0, ns.height > 0 else { return }
        let rect = AVMakeRect(aspectRatio: ns, insideRect: container)
        // 只在变化时更新（避免重复 relayout）
        guard abs(rect.minX - videoRect.minX) > 0.5 || abs(rect.width - videoRect.width) > 0.5 || videoRect.isEmpty else { return }
        videoRect = rect
        DYLog.shared.log("LIVE videoRect ns=\(Int(ns.width))x\(Int(ns.height)) rect=(\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height)))")
        // 弹幕 overlay 移到视频区左下角
        positionChatOverlay()
        // 标题层（collectionView 的 cell）也要按 videoRect 重排 → 触发 cell layoutSubviews
        collectionView?.setNeedsLayout()
    }

    /// v219：把弹幕 overlay 定位到视频区左下角（frame 布局）
    private func positionChatOverlay() {
        guard !videoRect.isEmpty else { return }
        let w = videoRect.width - 48
        let h: CGFloat = 344
        chatOverlay.frame = CGRect(x: videoRect.minX + 24, y: videoRect.maxY - 44 - h, width: w, height: h)
        chatOverlay.setNeedsLayout()
    }

    /// v213：KSMEPlayer 解流失败处理（重试 1 次同 URL，仍失败 advance 跳下一房）。
    private func handleKSFailure() {
        guard !ksFailureHandling else { return }   // 防重入（error + finish 可能连发）
        ksFailureHandling = true
        if !ksRetryUsed {
            ksRetryUsed = true
            let url = currentPlayUrl; let rid = playingWebRid
            DYLog.shared.log("LIVE KS retry once webRid=\(rid) url=\(url.prefix(60))")
            playingWebRid = ""        // 清掉让 play() 的去重 guard 放行
            if let u = URL(string: url) { play(url: url, webRid: rid) }
        } else {
            DYLog.shared.log("LIVE KS retry exhausted, advance webRid=\(playingWebRid)")
            advance()
        }
    }

    /// v212：直播 KSOptions（KSMEPlayer 走 FFmpeg，认证用 formatContextOptions，直播零自定义头 v208 实锤）。
    private func makeKSOptions() -> KSOptions {
        let o = KSOptions()
        o.isLoopPlay = true   // 直播流断了自动重连
        // 缓冲 preferredForwardBufferDuration 保持默认 3.0——v210 教训：直播缓冲参数乱动会回归，先不碰。
        return o
    }


    /// 直播流 header（照 VOD playbackHeaders web 分支：Referer+UA+ttwid；绝不加 sec-ch-ua，v157 铁律）
    private func liveHeaders() -> [String: String] {
        var h: [String: String] = [:]
        h["User-Agent"] = DYLiveClient.liveUA
        h["Referer"] = "https://live.douyin.com/"
        let ttwid = DYDanmakuClient.shared.ttwidValue
        if !ttwid.isEmpty { h["Cookie"] = "ttwid=\(ttwid)" }
        return h
    }

    private func loadMoreIfNeeded() {
        guard !DYLiveClient.shared.isLoadingMore else { return }
        DYLiveClient.shared.loadMore { [weak self] fresh in
            guard let self, !fresh.isEmpty else { return }
            self.collectionView.reloadData()
        }
    }

    // MARK: 遥控（照 NativePlayerView pressesBegan：上下切房，Menu 关闭走 SwiftUI onExitCommand）
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if DYQuickPanelModel.shared.isProfileOpen || DYQuickPanelModel.shared.isCommentOpen
                || DYQuickPanelModel.shared.isMixOpen {
            super.pressesBegan(presses, with: event)
            return
        }
        for press in presses {
            switch press.type {
            case .downArrow: advance(); return
            case .upArrow: rewind(); return
            default: break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    deinit {
        // v213：退出直播屏断开弹幕 WS + 停心跳（防泄漏/后台空转）
        danmakuSocket.disconnect()
    }
}

extension DYLiveFeedViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        DYLiveClient.shared.rooms.count
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! LivePlayerCell
        let idx = indexPath.item
        let rooms = DYLiveClient.shared.rooms
        if rooms.indices.contains(idx) {
            let room = rooms[idx]
            let viewerText = room.userCount.isEmpty ? "" : "\(room.userCount)观看"
            cell.videoRect = videoRect
            cell.configure(room: room, viewerText: viewerText)
        }
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        collectionView.bounds.size
    }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, withTargetContentOffset targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let pageHeight = max(1, scrollView.bounds.height)
        let targetY = targetContentOffset.pointee.y
        let snappedY = (velocity.y >= 0 ? ceil(targetY / pageHeight) : floor(targetY / pageHeight)) * pageHeight
        targetContentOffset.pointee.y = snappedY
    }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updatePlaybackStates(center: centeredIndex())
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updatePlaybackStates(center: centeredIndex())
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // v219：布局变化（旋转/初次布局）时重算视频显示区域 → 弹幕/标题跟随
        updateVideoRect()
        if !didInitialScroll, !DYLiveClient.shared.rooms.isEmpty, collectionView.bounds.height > 0 {
            didInitialScroll = true
            let idx = min(currentIndex, DYLiveClient.shared.rooms.count - 1)
            currentIndex = idx
            scrollTo(index: idx, animated: false)
        }
    }
}
