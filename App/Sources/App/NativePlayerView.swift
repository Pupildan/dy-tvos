import UIKit
import AVKit
import AVFoundation
import SwiftUI
import Combine

/// 承载单个 AVPlayer 的容器 view：AVPlayerLayer 铺满，供 Cell 持有。
final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
}

/// Feed Cell：不自己创建 Player。willDisplay 时向 PlayerManager 申请绑定对应的 Player 层。
/// 未就绪时显示高清封面 CoverImageView 兜底（绝不强行 play），避免黑屏。
/// v143 PC 版 UI：左下作者/文案区 + 右侧动作轨（计数纯展示，随视频自动切换）。
final class PlayerCell: UICollectionViewCell {
    let playerLayerView = PlayerLayerView()
    /// 弹幕覆盖层：真实视频层之上、封面之下（未 ready 时被封面盖住）；tvOS 焦点隔离（渲染纯展示层）
    let danmakuOverlay = DanmakuOverlay()
    /// 高清封面兜底：player 未 ready 时显示，绝不黑屏
    let coverImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.backgroundColor = .black
        iv.isHidden = true
        return iv
    }()
    // MARK: PC 版 UI（v143/v144）——左下信息区
    private let nicknameLabel = UILabel()
    private let descLabel = UILabel()
    private let hashtagLabel = UILabel()
    // MARK: PC 版 UI——右侧动作轨
    private let railAvatarView = UIImageView()
    private var railLikeIcon = UIImageView()
    private let railLikeLabel = UILabel()
    private var railCommentIcon = UIImageView()
    private let railCommentLabel = UILabel()
    private var railStarIcon = UIImageView()
    private let railStarLabel = UILabel()
    private var railShareIcon = UIImageView()
    private let railShareLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        contentView.addSubview(playerLayerView)
        contentView.addSubview(danmakuOverlay)
        contentView.addSubview(coverImageView)
        playerLayerView.playerLayer.videoGravity = .resizeAspect
        buildPCOverlay()
        // 焦点隔离实验：把 cell 彻底排除出 tvOS 焦点系统，验证跳多页是否焦点引擎作怪
        isUserInteractionEnabled = false
    }
    override var canBecomeFocused: Bool { false }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayerView.frame = contentView.bounds
        danmakuOverlay.frame = contentView.bounds
        coverImageView.frame = contentView.bounds
        layoutPCOverlay()
    }

    /// PC 版 UI 构建（层级：player < danmaku < cover < PC 信息层——封面期一并盖住）
    /// v144 修正：去上下箭头、去左下头像；昵称字号大于标题；昵称后跟发布时间；文案自动换行；话题独立行。
    private func buildPCOverlay() {
        // 左下：@昵称+发布时间 / 文案(3行自动换行) / 话题(独立行)
        nicknameLabel.font = .boldSystemFont(ofSize: 32)
        nicknameLabel.textColor = .white
        nicknameLabel.shadowColor = .black
        nicknameLabel.shadowOffset = CGSize(width: 1, height: 1)
        descLabel.font = .systemFont(ofSize: 26, weight: .medium)
        descLabel.textColor = .white
        descLabel.shadowColor = .black
        descLabel.shadowOffset = CGSize(width: 1, height: 1)
        descLabel.numberOfLines = 3
        hashtagLabel.font = .systemFont(ofSize: 24, weight: .medium)
        hashtagLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        hashtagLabel.shadowColor = .black
        hashtagLabel.shadowOffset = CGSize(width: 1, height: 1)
        contentView.addSubview(nicknameLabel)
        contentView.addSubview(descLabel)
        contentView.addSubview(hashtagLabel)

        // 右侧动作轨（纯展示；图标 SF Symbols，计数万缩写；v144 去掉上下箭头）
        func railIcon(_ name: String) -> UIImageView {
            let iv = UIImageView(image: UIImage(systemName: name))
            iv.tintColor = .white
            iv.contentMode = .center
            return iv
        }
        railAvatarView.contentMode = .scaleAspectFill
        railAvatarView.clipsToBounds = true
        railAvatarView.layer.cornerRadius = 33
        railAvatarView.layer.borderColor = UIColor.white.withAlphaComponent(0.7).cgColor
        railAvatarView.layer.borderWidth = 2
        railLikeIcon = railIcon("heart.fill")
        railCommentIcon = railIcon("bubble.left.fill")
        railStarIcon = railIcon("star.fill")
        railShareIcon = railIcon("arrowshape.turn.up.right.fill")
        for l in [railLikeLabel, railCommentLabel, railStarLabel, railShareLabel] {
            l.font = .systemFont(ofSize: 24, weight: .semibold)
            l.textColor = .white
            l.textAlignment = .center
        }
        for v in [railAvatarView, railLikeIcon, railLikeLabel, railCommentIcon, railCommentLabel, railStarIcon, railStarLabel, railShareIcon, railShareLabel] {
            contentView.addSubview(v)
        }
    }

    /// PC 版 UI 布局（右轨距右 118px 竖排起于 28% 高度；左下信息区避让进度条，底部锚定向上排）
    private func layoutPCOverlay() {
        let b = contentView.bounds
        let railX = b.width - 118
        let railW: CGFloat = 92
        var y = b.height * 0.32
        railAvatarView.frame = CGRect(x: railX + 16, y: y, width: 66, height: 66); y += 78
        for (icon, label) in [(railLikeIcon, railLikeLabel), (railCommentIcon, railCommentLabel), (railStarIcon, railStarLabel), (railShareIcon, railShareLabel)] {
            icon.frame = CGRect(x: railX, y: y, width: railW, height: 44)
            label.frame = CGRect(x: railX - 14, y: y + 44, width: railW + 28, height: 30)
            y += 84
        }
        // 左下信息区（无头像；底部锚定向上：话题 → 文案(3行) → 昵称+时间）
        let infoLeft: CGFloat = 24
        let infoBottom: CGFloat = 40
        let infoW = b.width - railW - 160
        hashtagLabel.frame = CGRect(x: infoLeft, y: b.height - infoBottom - 34, width: infoW, height: 34)
        descLabel.frame = CGRect(x: infoLeft, y: b.height - infoBottom - 34 - 8 - 102, width: infoW, height: 102)
        nicknameLabel.frame = CGRect(x: infoLeft, y: b.height - infoBottom - 34 - 8 - 102 - 8 - 42, width: infoW, height: 42)
    }

    /// 绑定 PlayerManager 分配的 player（Cell 不创建、不持有 player 生命周期）。
    func bind(player: AVPlayer) {
        playerLayerView.player = player
    }

    /// 填充 PC 版 UI 数据（willDisplay 时按 index 调用）。
    func applyInfo(_ info: DYVideoInfo?) {
        // 昵称 + 发布时间（同一行：名字号大于标题字号）
        let nick = info?.nickname.isEmpty == false ? "@\(info!.nickname)" : ""
        let time = info?.createTimeText ?? ""
        if nick.isEmpty && time.isEmpty {
            nicknameLabel.attributedText = nil
        } else {
            let s = NSMutableAttributedString()
            if !nick.isEmpty {
                s.append(NSAttributedString(string: nick, attributes: [.font: UIFont.boldSystemFont(ofSize: 32), .foregroundColor: UIColor.white, .shadow: Self.textShadow]))
                if !time.isEmpty { s.append(NSAttributedString(string: "  ·  ", attributes: [.font: UIFont.systemFont(ofSize: 26), .foregroundColor: UIColor.white.withAlphaComponent(0.7), .shadow: Self.textShadow])) }
            }
            if !time.isEmpty {
                s.append(NSAttributedString(string: time, attributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.white.withAlphaComponent(0.75), .shadow: Self.textShadow]))
            }
            nicknameLabel.attributedText = s
        }
        descLabel.text = info?.desc.isEmpty == false ? info?.desc : nil
        hashtagLabel.text = info?.hashtags.isEmpty == false ? info?.hashtags : nil
        railAvatarView.image = nil
        if let urlStr = info?.avatarUrl, let url = URL(string: urlStr) {
            AvatarLoader.shared.load(url) { [weak self] img in
                self?.railAvatarView.image = img
            }
        }
        railLikeLabel.text = Self.cnCount(info?.digg ?? 0)
        railCommentLabel.text = Self.cnCount(info?.comment ?? 0)
        railStarLabel.text = Self.cnCount(info?.collect ?? 0)
        railShareLabel.text = Self.cnCount(info?.share ?? 0)
    }

    /// 文字阴影（左下信息区可读性）
    private static let textShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = UIColor.black
        s.shadowOffset = CGSize(width: 1, height: 1)
        s.shadowBlurRadius = 2
        return s
    }()

    /// 数字万/亿缩写（3.9万 / 1.2亿），对齐 PC 版风格。
    static func cnCount(_ n: Int) -> String {
        if n >= 100_000_000 { return String(format: "%.1f亿", Double(n) / 100_000_000) }
        if n >= 10_000 { return String(format: "%.1f万", Double(n) / 10_000) }
        return String(n)
    }
    /// 设置封面兜底图。
    func setCover(_ image: UIImage?) {
        coverImageView.image = image
    }
    /// 封面显隐：player 未 ready 时显示封面，ready 后隐藏露出真实视频层。
    func setCoverVisible(_ visible: Bool) {
        coverImageView.isHidden = !visible
    }
}

/// 全局唯一 Player 管理器：最多维护 3 个 AVPlayer（current-1 / current / current+1）。
/// 按需分配 + 按距离驱逐：超出 [idx-1, idx+1] 的 player 立刻 pause + replaceCurrentItem(nil)，
/// 强制系统瞬间回收解码器——根治"解码器耗尽→黑屏"。Cell 不创建 player，只绑定。
final class PlayerManager {
    static let shared = PlayerManager()
    /// 上限池：index -> AVPlayer
    private var players: [Int: AVPlayer] = [:]
    /// 冷启动待补装载的邻居 index（首个 prepare 只装居中条，居中 ready 后补齐）
    private var pendingNeighbors: Set<Int> = []
    /// index -> 封面图（异步生成后缓存，未 ready 时兜底）
    private var covers: [Int: UIImage] = [:]
    private var coversLoading = Set<Int>()
    /// player ready 变化回调（index）——供控制器刷新封面显隐
    var onPlayerReady: ((Int) -> Void)?
    /// 无视频轨回调（index，已 0.6s 复查确认）——控制器决定是否跳过（仅居中会跳）
    var onNoVideoTrack: ((Int) -> Void)?
    private var readyObservers: [Int: NSKeyValueObservation] = [:]
    /// 静态直链保鲜期（秒）：douyinvod 直链 URL 内嵌时效签名，实测超龄后 Cannot Open → 黑屏。
    /// 超过此年龄的静态直链改用 /aweme/v1/play 重定向端点（服务器现场 302 出新鲜直链）。
    private let staleSeconds: TimeInterval = 90

    private init() {}

    /// 滑动到 idx：确保 [idx-2, idx+2] 有 player，驱逐范围外的（pause + 置空 item 回收解码器）。
    /// 窗口放宽到 ±2：来回微抖时有缓冲余量，不会一抖就 evict 刚 ready 的（±1 会抖动→黑屏）。
    /// 只从 scrollTo(最终目标 index) 调用；updatePlaybackStates/willDisplay 只查池不触驱逐（杜绝双 center 打架抖动）。
    func prepare(center idx: Int) {
        let desired = [idx - 2, idx - 1, idx, idx + 1, idx + 2].filter { $0 >= 0 && PlaybackEngine.shared.urls.indices.contains($0) }
        // 1) 驱逐范围外的 player：pause + replaceCurrentItem(nil) 强制回收解码器
        for (i, p) in players where !desired.contains(i) {
            p.pause()
            p.replaceCurrentItem(with: nil)   // 关键：置空 item，系统瞬间回收解码器
            readyObservers[i]?.invalidate()
            readyObservers.removeValue(forKey: i)
            players.removeValue(forKey: i)
            DYLog.shared.log("MGR evict idx=\(i)")
        }
        // 2) 冷启动收敛（v130）：池全空=会话首个 prepare → 只装载居中条且直接走重定向直链。
        // v129 实锤：启动 idx=0 静态直链（age=0）4s 不 ready + idx=1 并发 TLS error，repair 换
        // redirect 后 4s ready——redirect 优先省掉一次 4s 空等+重建来回；邻居推迟装载，
        // 避免启动瞬间 3 个并发 TLS 握手互相拖垮。居中 ready 后由 drainPendingNeighbors 补齐。
        if players.isEmpty {
            if PlaybackEngine.shared.urls.indices.contains(idx) {
                acquire(index: idx, forceRedirect: true)
            }
            pendingNeighbors = Set(desired.filter { $0 != idx })
            DYLog.shared.log("MGR cold-start defer neighbors=\(pendingNeighbors.sorted())")
            DYLog.shared.count("cold_start")
            return
        }
        // 3) 正常路径：确保范围内的都存在（复用已有，缺失才建）
        if !pendingNeighbors.isEmpty { pendingNeighbors.removeAll() }
        for i in desired where players[i] == nil {
            acquire(index: i)
        }
    }

    /// 冷启动收敛第二步：居中条 ready 后补装载邻居（此时网络已暖，静态直链快启动）。
    private func drainPendingNeighbors() {
        guard !pendingNeighbors.isEmpty else { return }
        let pend = pendingNeighbors.sorted()
        pendingNeighbors.removeAll()
        for i in pend {
            if players[i] == nil, PlaybackEngine.shared.urls.indices.contains(i) {
                acquire(index: i)
            }
        }
        DYLog.shared.log("MGR cold-start neighbors acquired=\(pend)")
    }

    /// 取 index 的 player（prepare 已确保存在；防御性：缺失则现建）。
    func player(at index: Int) -> AVPlayer? {
        if let p = players[index] { return p }
        guard PlaybackEngine.shared.urls.indices.contains(index) else { return nil }
        return acquire(index: index)
    }

    /// 纯查询（不 acquire、不驱逐）：池里有就返回，没有返回 nil。willDisplay 用它，避免快速滑动撑大池。
    func peekPlayer(at index: Int) -> AVPlayer? {
        players[index]
    }

    /// index 的封面兜底图（异步生成，未就绪返回 nil，生成完回调刷新）。
    /// 静态直链过期时封面同样生成失败 → 用重定向直链重试一次（与播放选链同源逻辑，防封面黑屏）。
    func cover(at index: Int, completion: @escaping (UIImage?) -> Void) {
        if let img = covers[index] { completion(img); return }
        guard PlaybackEngine.shared.urls.indices.contains(index) else { completion(nil); return }
        if coversLoading.contains(index) { completion(nil); return }
        coversLoading.insert(index)
        let staticURL = PlaybackEngine.shared.urls[index]
        let redirect = PlaybackEngine.shared.redirectURL(at: index)
        let finish: (UIImage?) -> Void = { [weak self] img in
            DispatchQueue.main.async {
                self?.coversLoading.remove(index)
                completion(img)
            }
        }
        generateCover(url: staticURL) { [weak self] img in
            if let img {
                self?.covers[index] = img
                finish(img)
                return
            }
            guard let redirect else { finish(nil); return }
            DYLog.shared.log("COVER retry redirect idx=\(index)")
            DYLog.shared.count("cover_retry")
            self?.generateCover(url: redirect) { img2 in
                if let img2 { self?.covers[index] = img2 }
                finish(img2)
            }
        }
    }

    /// 用单个 URL 生成封面帧（静态/重定向直链共用）。
    private func generateCover(url: URL, completion: @escaping (UIImage?) -> Void) {
        var headers = ["User-Agent": DYFeedClient.mobileUA]
        if let cookie = DYFeedClient.shared.cookieHeaderForPlayback(), !cookie.isEmpty {
            headers["Cookie"] = cookie
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1080, height: 1920)
        gen.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime.zero)]) { _, cg, _, result, _ in
            DispatchQueue.main.async {
                guard result == .succeeded, let cg else { completion(nil); return }
                completion(UIImage(cgImage: cg))
            }
        }
    }

    /// 播放请求头按源切换（v135）：mobile=移动端 UA/Cookie；web=Chrome UA+Referer+ttwid（web CDN 需要）
    private func playbackHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        if PlaybackEngine.shared.source == .web {
            headers["User-Agent"] = DYDanmakuClient.webUA
            headers["Referer"] = "https://www.douyin.com/"
            let ttwid = DYDanmakuClient.shared.ttwidValue
            if !ttwid.isEmpty { headers["Cookie"] = "ttwid=\(ttwid)" }
        } else {
            headers["User-Agent"] = DYFeedClient.mobileUA
            if let cookie = DYFeedClient.shared.cookieHeaderForPlayback(), !cookie.isEmpty {
                headers["Cookie"] = cookie
            }
        }
        return headers
    }

    /// 播放时选链（v128，照 myDV selectBestPlayUrl 优先级适配）：
    /// 静态直链年龄 ≤ staleSeconds → 用静态（快启动、全清晰度）；
    /// 超龄且备有重定向直链 → 用 /aweme/v1/play 重定向端点（URL 不带时效签名，
    /// 服务器在请求瞬间 302 出新鲜 CDN 直链，AVPlayer 自动跟随）——真·现取新鲜。
    /// ⚠️ v122 旧实现"用 rawVideos 重跑 pickHighestQuality"被日志证伪（381 次 fallback/0 次成功）：
    /// bytes 里只有同一批静态链接，重解析永远选不出新 URL——新鲜只能靠重新网络请求。
    private func resolveFreshURL(index: Int, forceRedirect: Bool) -> URL {
        let engine = PlaybackEngine.shared
        let age = engine.urlAge(at: index)
        let staticURL = engine.urls.indices.contains(index) ? engine.urls[index] : nil
        let redirect = engine.redirectURL(at: index)
        if forceRedirect, let redirect {
            DYLog.shared.log("MGR url idx=\(index) src=redirect forced")
            DYLog.shared.count("url_redirect")
            return redirect
        }
        if let staticURL, age <= staleSeconds {
            DYLog.shared.log("MGR url idx=\(index) src=static age=\(Int(age))s")
            DYLog.shared.count("url_static")
            return staticURL
        }
        if let redirect {
            DYLog.shared.log("MGR url idx=\(index) src=redirect age=\(Int(age))s stale")
            DYLog.shared.count("url_redirect")
            return redirect
        }
        // 无重定向可用（理论少见）：陈旧静态也是唯一选择
        DYLog.shared.log("MGR url idx=\(index) src=static-stale-no-redirect age=\(Int(age))s")
        DYLog.shared.count("url_static_stale")
        if let staticURL { return staticURL }
        return redirect ?? engine.urls.first ?? URL(fileURLWithPath: "/dev/null")
    }

    /// 新建 player 装载 index，挂 status KVO：
    /// ready → onPlayerReady 刷新封面显隐 + 视频轨检测（空则 0.6s 复查后判黑屏无声）；
    /// failed → 只记日志不自动跳（v121 教训：自动跳会跳多页），交给看门狗统一处理。
    private func acquire(index: Int, forceRedirect: Bool = false) -> AVPlayer {
        let url = resolveFreshURL(index: index, forceRedirect: forceRedirect)
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": playbackHeaders()])
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 8
        let p = AVPlayer()
        p.replaceCurrentItem(with: playerItem)
        players[index] = p
        readyObservers[index]?.invalidate()
        readyObservers[index] = playerItem.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            if observedItem.status == .failed {
                let err = observedItem.error?.localizedDescription ?? "?"
                DispatchQueue.main.async {
                    DYLog.shared.event("MGR itemErr idx=\(index) err=\(err)")
                    DYLog.shared.count("itemErr")
                }
                return
            }
            guard observedItem.status == .readyToPlay else { return }
            DispatchQueue.main.async {
                self?.onPlayerReady?(index)
                DYLog.shared.log("MGR ready idx=\(index)")
                DYLog.shared.count("ready")
                self?.drainPendingNeighbors()
            }
            // 黑屏无声检测：ready 但无视频轨（图集/纯音频/无效媒体；v124 实锤 idx=31 codec=no-video-track）。
            // 0.6s 后复查一次防异步误杀（v119 教训：ready 瞬间轨可能未加载完）。
            // 用 asset.loadTracks（异步等待加载完，tvOS 15+）——不用 item.tracks(withMediaType:)，
            // 它与属性 tracks 在 Swift 里重载冲突（CI 实锤 error: non-function type）。
            // identity 守卫：该 index 已被驱逐/重建（currentItem 换了）则不判，防旧 item 延迟回调误伤。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard observedItem.status == .readyToPlay,
                          self.players[index]?.currentItem === observedItem else { return }
                    let videoTracks = (try? await observedItem.asset.loadTracks(withMediaType: AVMediaType.video)) ?? []
                    if videoTracks.isEmpty {
                        DYLog.shared.event("MGR novideo idx=\(index) (double-checked)")
                        DYLog.shared.count("novideo")
                        self.onNoVideoTrack?(index)
                    }
                }
            }
        }
        DYLog.shared.log("MGR acquire idx=\(index) total=\(players.count)")
        DYLog.shared.count("acquire")
        return p
    }

    /// 看门狗修复动作：就地换源——驱逐旧 player，强制走重定向直链现取新鲜 URL 重建。
    /// 照 myDV onPlayerError「先重试一次 prepare 再跳过」的思路，把"跳过"降级为兜底。
    func rebuildWithRedirect(index: Int) {
        if let p = players[index] {
            p.pause()
            p.replaceCurrentItem(with: nil)
        }
        readyObservers[index]?.invalidate()
        readyObservers.removeValue(forKey: index)
        players.removeValue(forKey: index)
        DYLog.shared.log("MGR rebuild idx=\(index) (redirect)")
        _ = acquire(index: index, forceRedirect: true)
    }
}

/// 头像异步加载（NSCache 记忆化；PC 版 UI 头像用）。
final class AvatarLoader {
    static let shared = AvatarLoader()
    private let cache = NSCache<NSURL, UIImage>()

    func load(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        if let img = cache.object(forKey: url as NSURL) { completion(img); return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let img = data.flatMap(UIImage.init(data:))
            if let img { self?.cache.setObject(img, forKey: url as NSURL) }
            DispatchQueue.main.async { completion(img) }
        }.resume()
    }
}

/// 底部播放进度条（v140）：液态玻璃细条贴屏幕底部，低调但可辨。纯展示（左右键 seek 已有，条随 seek 跳动）。
final class DYProgressBar: UIView {
    private let blurView: UIVisualEffectView
    private let fillLayer = CALayer()
    private var ratio: Double = 0

    override init(frame: CGRect) {
        blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))   // tvOS 专属样式（system* 系列在 tvOS 不可用）
        super.init(frame: frame)
        backgroundColor = .clear
        layer.cornerRadius = 2.5
        layer.masksToBounds = true
        // 液态玻璃质感：细窄系统材质底 + 白色进度
        blurView.frame = bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.alpha = 0.55   // 低调：仔细看才明显
        addSubview(blurView)
        fillLayer.backgroundColor = UIColor.white.withAlphaComponent(0.75).cgColor
        fillLayer.cornerRadius = 2.5
        blurView.contentView.layer.addSublayer(fillLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        applyRatio()
    }

    /// current/duration 秒；duration 无效时整条隐藏。
    func update(current: Double, duration: Double) {
        guard duration > 1, current.isFinite, duration.isFinite else {
            isHidden = true
            return
        }
        isHidden = false
        ratio = min(1, max(0, current / duration))
        applyRatio()
    }

    private func applyRatio() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // 进度推进不做隐式动画（0.5s tick 步进即可）
        fillLayer.frame = CGRect(x: 0, y: 0, width: bounds.width * CGFloat(ratio), height: bounds.height)
        CATransaction.commit()
    }
}

/// 原生播放器：UICollectionView 垂直分页 + PlayerManager 上限 3 池。
/// 真实图层滑动（铁律）：滑动=前后 Cell 连同真实视频画面一起位移（UIScrollView 原生物理）。
/// 解码器上限 3（current±1）+ 超范围驱逐回收 → 根治解码器耗尽黑屏；未就绪显示封面兜底 → 无黑屏。
final class DYPlayerViewController: UIViewController {
    private var cancellables = Set<AnyCancellable>()
    private var collectionView: UICollectionView!
    private var currentIndex = 0
    private var didInitialScroll = false
    /// 底部播放进度条（v140：液态玻璃细条，纯展示）
    private let progressBar = DYProgressBar(frame: .zero)
    private var progressTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        view.backgroundColor = .black
        DYLog.shared.log("FEEDCOLL viewDidLoad")

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
        collectionView.register(PlayerCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.showsVerticalScrollIndicator = false
        view.addSubview(collectionView)
        // 底部播放进度条（最顶层；0.5s 随播放推进，seek 即时跳动）
        view.addSubview(progressBar)
        let pt = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.updateProgress() }
        RunLoop.main.add(pt, forMode: .common)
        progressTimer = pt

        PlaybackEngine.shared.$urls
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reloadIfNeeded() }
            .store(in: &cancellables)
        // player ready → 刷新可见 cell 封面显隐（ready 的隐藏封面露出真实视频）
        PlayerManager.shared.onPlayerReady = { [weak self] idx in
            self?.refreshCoverForVisible()
        }
        // 无视频轨（已 0.6s 复查确认）→ 统一跳过入口（护栏内：仅居中才跳）
        PlayerManager.shared.onNoVideoTrack = { [weak self] idx in
            self?.skipIfCentered(idx, reason: "novideo")
        }
        startWatchdog()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.height > 0 else { return }
        collectionView.frame = view.bounds
        // 进度条贴屏幕最底部（左右留 24px，高 5px）
        progressBar.frame = CGRect(x: 24, y: view.bounds.height - 13, width: view.bounds.width - 48, height: 5)
        if !didInitialScroll, !PlaybackEngine.shared.urls.isEmpty {
            didInitialScroll = true
            scrollTo(index: PlaybackEngine.shared.index, animated: false)
        }
        for cell in collectionView.visibleCells {
            (cell as? PlayerCell)?.playerLayerView.frame = (cell as? PlayerCell)?.contentView.bounds ?? .zero
            (cell as? PlayerCell)?.coverImageView.frame = (cell as? PlayerCell)?.contentView.bounds ?? .zero
        }
    }

    /// 进度条刷新（0.5s）：当前居中 player 的 currentTime/duration
    private func updateProgress() {
        guard let p = PlayerManager.shared.player(at: currentIndex),
              let item = p.currentItem else { progressBar.update(current: 0, duration: 0); return }
        let dur = item.duration.seconds
        let cur = item.currentTime().seconds
        progressBar.update(current: cur, duration: dur)
    }

    private var lastKnownCount = 0

    private func reloadIfNeeded() {
        let newCount = PlaybackEngine.shared.urls.count
        guard newCount > 0 else {
            // 空态（v135 源切换后引擎 reset）：视图整体重置，等新源首批
            if lastKnownCount != 0 {
                lastKnownCount = 0
                collectionView.reloadData()
                DYLog.shared.log("FEEDCOLL reset view (source switch)")
            }
            return
        }
        let oldCount = lastKnownCount
        if oldCount == 0 {
            // 首批：全量建池（一次性）
            collectionView.reloadData()
            lastKnownCount = newCount
            scrollTo(index: PlaybackEngine.shared.index, animated: false)
            return
        }
        guard newCount > oldCount else { return }
        // 翻页增量插入：只插入新增的 index，不动已有 cell/player 池（避免 reloadData 全量重建
        // 摧毁已缓冲 player → 居中瞬黑屏，且刷越多页 merge 越频繁黑屏概率越大）
        var newIdx: [IndexPath] = []
        for i in oldCount..<newCount { newIdx.append(IndexPath(item: i, section: 0)) }
        collectionView.performBatchUpdates({
            collectionView.insertItems(at: newIdx)
        }, completion: nil)
        lastKnownCount = newCount
        // 引擎 index 已在新增范围外时（罕见）校正，正常翻页 index 落在已有区间无需滚动
        let idx = PlaybackEngine.shared.index
        if idx >= newCount {
            scrollTo(index: newCount - 1, animated: false)
        }
    }

    // MARK: - 滚动驱动

    private func canScrollTo(index: Int) -> Bool {
        guard collectionView.window != nil,
              collectionView.bounds.height > 0,
              !PlaybackEngine.shared.urls.isEmpty else { return false }
        collectionView.layoutIfNeeded()
        return true
    }

    private func scrollTo(index: Int, animated: Bool) {
        guard canScrollTo(index: index) else {
            DYLog.shared.log("FEEDCOLL scrollTo SKIP idx=\(index) (not laid out / no data)")
            return
        }
        let count = PlaybackEngine.shared.urls.count
        guard index >= 0, index < count else { return }
        let clampedIndex = min(max(0, index), count - 1)
        // setContentOffset 替代 scrollToItem（后者 flow layout 未就绪会抛 NSException，.ips 已定位）
        let pageHeight = max(1, collectionView.bounds.height)
        let maxOffset = max(0, collectionView.contentSize.height - collectionView.bounds.height)
        let targetY = min(CGFloat(clampedIndex) * pageHeight, maxOffset)
        collectionView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
        currentIndex = clampedIndex
        // 对齐引擎索引 + 接近末尾翻页
        let engine = PlaybackEngine.shared
        if clampedIndex > engine.index {
            for _ in engine.index..<clampedIndex { engine.next() }
        } else if clampedIndex < engine.index {
            for _ in clampedIndex..<engine.index { engine.prev() }
        }
        if engine.count > 0, clampedIndex >= engine.count - 7 {
            engine.triggerNeedMore()
        }
        // 核心：让 PlayerManager 只保留 [idx-1, idx+1] 三个 player，超范围驱逐回收解码器
        PlayerManager.shared.prepare(center: clampedIndex)
        DYLog.shared.log("FEEDCOLL scrollTo idx=\(clampedIndex) y=\(targetY) items=\(count)")
        DYLog.shared.count("scroll")
        // 看门狗状态复位：新 center 重新观察（修复标记/宽限期/计数全清）
        repairedFor = nil
        graceUntil = .distantPast
        resetWatchCounters()
        // 滚动到位刷新播放态 + 封面显隐
        DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.35 : 0.05)) { [weak self] in
            self?.updatePlaybackStates(center: clampedIndex)
        }
    }

    /// 居中 Cell 播放（player 已 ready），非居中暂停；未 ready 的显示封面兜底，绝不强行 play。
    /// 不调 prepare（那会用 centeredIndex 和 scrollTo 的目标 index 打架→池抖动→黑屏）；只查池控播放态。
    /// 弹幕同步：居中在播 → load(换片)+play；否则 pause。
    private func updatePlaybackStates(center index: Int) {
        for cell in collectionView.visibleCells {
            guard let c = cell as? PlayerCell,
                  let ip = collectionView.indexPath(for: c) else { continue }
            let idx = ip.item
            let isCenter = (idx == index)
            if let p = PlayerManager.shared.player(at: idx) {
                c.bind(player: p)
                let ready = (p.currentItem?.status == .readyToPlay)
                if isCenter, ready {
                    p.play()
                    c.setCoverVisible(false)
                    c.danmakuOverlay.bind(player: p)
                    c.danmakuOverlay.load(awemeId: PlaybackEngine.shared.awemeId(at: idx) ?? "",
                                          durationMs: PlaybackEngine.shared.durationMs(at: idx))
                    c.danmakuOverlay.syncPlaying(true)
                } else {
                    p.pause()
                    // 未 ready（或非居中）显示封面兜底
                    if !ready { loadCover(for: c, index: idx) }
                    c.setCoverVisible(!ready)
                    c.danmakuOverlay.syncPlaying(false)
                }
            } else {
                // 无 player（超范围）：显示封面兜底
                loadCover(for: c, index: idx)
                c.setCoverVisible(true)
            }
        }
    }

    /// 异步取封面兜底图（未就绪时不黑屏）。
    private func loadCover(for cell: PlayerCell, index: Int) {
        PlayerManager.shared.cover(at: index) { [weak cell] img in
            cell?.setCover(img)
        }
    }

    /// player ready 回调：隐藏对应可见 cell 的封面，露出真实视频。
    private func refreshCoverForVisible() {
        for cell in collectionView.visibleCells {
            guard let c = cell as? PlayerCell,
                  let ip = collectionView.indexPath(for: c),
                  let p = PlayerManager.shared.player(at: ip.item) else { continue }
            if p.currentItem?.status == .readyToPlay {
                c.setCoverVisible(false)
                if ip.item == currentIndex {
                    p.play()
                    c.danmakuOverlay.bind(player: p)
                    c.danmakuOverlay.load(awemeId: PlaybackEngine.shared.awemeId(at: ip.item) ?? "",
                                          durationMs: PlaybackEngine.shared.durationMs(at: ip.item))
                    c.danmakuOverlay.syncPlaying(true)
                }
            }
        }
    }

    /// 当前居中的 item index。
    private func centeredIndex() -> Int {
        guard collectionView.bounds.height > 0 else { return currentIndex }
        let center = CGPoint(x: collectionView.bounds.midX, y: collectionView.bounds.midY)
        if let ip = collectionView.indexPathForItem(at: center) { return ip.item }
        return Int(round(collectionView.contentOffset.y / max(1, collectionView.bounds.height)))
    }

    // MARK: - 看门狗（v128 统一三层检测：idle 一直不 ready / stall 时间停滞 / black 有播放无首帧）
    // 动作阶梯：先 repair（换重定向直链就地重建，照 myDV onPlayerError 先重试）→ 仍异常才 skip。
    // 护栏：只监控居中（index==engine.index）；连续自动跳 ≥3 停手等用户；绝不用 centeredIndex 反推。

    /// 修复后缓冲宽限期（秒）：新 player 需要重新装载，期间只观察不动作
    private let watchGraceSeconds: TimeInterval = 6
    private let watchIdleTicks = 2     // status 非 ready 连续 2s → idle（v130 由 4s 下调：repair 实测 1-2s 恢复，静态直链打不开少等 2s）
    private let watchStallTicks = 3    // ready+非暂停但时间停滞连续 3s → stall（有轨但解不出）
    private let watchBlackTicks = 2    // ready+时间在走但无首帧连续 2s → black（黑屏有声，v123 停滞看门狗的盲区）
    private var idleTicks = 0
    private var stallTicks = 0
    private var blackTicks = 0
    private var lastWatchTime: Double = -1
    private var repairedFor: Int? = nil
    private var graceUntil = Date.distantPast
    private var autoSkipStreak = 0     // 连续自动跳计数（手动按键/播放恢复健康时清零）
    private var autoSkipDisabled = false

    private func startWatchdog() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.watchTick() }
        RunLoop.main.add(t, forMode: .common)
    }

    /// 看门狗心跳（1s）。三层检测对应三类黑屏：
    /// idle=URL 无效（黑屏无声/停封面）；stall=有轨但时间不走（黑屏无声）；
    /// black=音频在走时间在走但首帧渲染不出（黑屏有声——v123 停滞看门狗永远抓不到的盲区）。
    private func watchTick() {
        guard isViewLoaded, view.window != nil, !PlaybackEngine.shared.urls.isEmpty else { return }
        let idx = currentIndex
        let engine = PlaybackEngine.shared
        guard idx == engine.index else { return }   // 护栏：引擎索引为唯一真相源
        guard let p = PlayerManager.shared.player(at: idx), let item = p.currentItem else { resetWatchCounters(); return }
        // 首帧信号：居中 cell 的 playerLayer.isReadyForDisplay（myDV onRenderedFirstFrame 的 AVPlayer 等价信号）
        let rfd: Bool
        if let cell = collectionView.cellForItem(at: IndexPath(item: idx, section: 0)) as? PlayerCell {
            rfd = cell.playerLayerView.playerLayer.isReadyForDisplay
        } else {
            rfd = false
        }
        let t = item.currentTime()
        let tSec = t.seconds.isFinite ? t.seconds : 0
        if lastWatchTime < 0 {
            lastWatchTime = tSec   // 首跳只采样不判断
            return
        }
        let advanced = tSec > lastWatchTime + 0.05
        lastWatchTime = tSec
        // 健康恢复：首帧已渲染且时间在走 → 清看门狗/自动跳状态
        if rfd && advanced {
            onPlayHealthy()
            return
        }
        // 修复后宽限期：只观察不动作（重建的 player 需要重新装载缓冲）
        if Date() < graceUntil { return }
        // 三层检测
        var reason: String? = nil
        if item.status != .readyToPlay {
            idleTicks += 1; stallTicks = 0; blackTicks = 0
            if idleTicks >= watchIdleTicks { reason = item.status == .failed ? "idle-failed" : "idle" }
        } else if p.timeControlStatus != .paused && !advanced {
            stallTicks += 1; idleTicks = 0; blackTicks = 0
            if stallTicks >= watchStallTicks { reason = "stall" }
        } else if p.timeControlStatus != .paused && advanced && !rfd {
            blackTicks += 1; idleTicks = 0; stallTicks = 0
            if blackTicks >= watchBlackTicks { reason = "black" }
        } else {
            resetWatchCounters()
        }
        guard let r = reason else { return }
        actOnWatch(index: idx, reason: r)
    }

    /// 检测命中 → 修复一次；修复后仍命中 → 跳过。
    private func actOnWatch(index: Int, reason: String) {
        if repairedFor != index {
            repairedFor = index
            DYLog.shared.event("WATCH repair idx=\(index) reason=\(reason)")
            DYLog.shared.count("repair")
            PlayerManager.shared.rebuildWithRedirect(index: index)
            updatePlaybackStates(center: index)
            graceUntil = Date().addingTimeInterval(watchGraceSeconds)
            resetWatchCounters()
            return
        }
        skipIfCentered(index, reason: reason)
    }

    /// 播放恢复健康（首帧渲染 + 时间前进）：清连续自动跳/看门狗状态。
    private func onPlayHealthy() {
        if autoSkipStreak > 0 || autoSkipDisabled {
            DYLog.shared.log("WATCH healthy idx=\(currentIndex) auto-skip streak reset")
        }
        autoSkipStreak = 0
        autoSkipDisabled = false
        repairedFor = nil
        resetWatchCounters()
    }

    private func resetWatchCounters() {
        idleTicks = 0
        stallTicks = 0
        blackTicks = 0
        lastWatchTime = -1
    }

    /// 统一跳过入口（看门狗/无轨检测共用）。护栏（v111/v112 血泪教训）：
    /// 1) 只跳居中（index==engine.index，非居中/中途反推会跳多页）；
    /// 2) 连续自动跳 ≥3 停手（防级联跳穿），等用户手动按键复位；
    /// 3) 跳过 = engine.next() + 显式 scrollTo 目标，绝不用 centeredIndex 反推。
    private func skipIfCentered(_ index: Int, reason: String) {
        let engine = PlaybackEngine.shared
        guard index == engine.index else {
            DYLog.shared.log("WATCH skip-guard idx=\(index) != engine=\(engine.index) (non-center)")
            return
        }
        if autoSkipDisabled {
            DYLog.shared.log("WATCH skip-disabled idx=\(index) (wait user key)")
            return
        }
        guard autoSkipStreak < 3 else {
            autoSkipDisabled = true
            DYLog.shared.event("WATCH cascade-stop idx=\(index) streak=3 (auto-skip disabled)")
            return
        }
        autoSkipStreak += 1
        DYLog.shared.event("WATCH skip idx=\(index) reason=\(reason) streak=\(autoSkipStreak)")
        DYLog.shared.count("autoskip")
        resetWatchCounters()
        repairedFor = nil
        engine.next()
        scrollTo(index: engine.index, animated: true)
    }

    private func advance() {
        scrollTo(index: centeredIndex() + 1, animated: true)
    }
    private func rewind() {
        scrollTo(index: max(0, centeredIndex() - 1), animated: true)
    }

    private func seek(by seconds: Double) {
        let idx = centeredIndex()
        guard let p = PlayerManager.shared.player(at: idx),
              let t = p.currentItem?.currentTime().seconds, t.isFinite else { return }
        let target = max(0, t + seconds)
        p.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        DYLog.shared.log("FEEDCOLL seek \(seconds)s -> \(target)")
        // 弹幕随 seek 清屏重对齐
        (collectionView.cellForItem(at: IndexPath(item: idx, section: 0)) as? PlayerCell)?.danmakuOverlay.seekSync()
    }
    private func togglePlayPause() {
        let idx = centeredIndex()
        guard let p = PlayerManager.shared.player(at: idx) else { return }
        let wasPlaying = (p.timeControlStatus == .playing)
        if wasPlaying { p.pause() } else { p.play() }
        if let cell = collectionView.cellForItem(at: IndexPath(item: idx, section: 0)) as? PlayerCell {
            cell.danmakuOverlay.syncPlaying(!wasPlaying)
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // 手动按键：复位自动跳护栏（连续跳停手后按任意键恢复）
        autoSkipStreak = 0
        autoSkipDisabled = false
        for press in presses {
            switch press.type {
            case .downArrow: advance(); return
            case .upArrow: rewind(); return
            case .leftArrow: seek(by: -10); return
            case .rightArrow: seek(by: 10); return
            case .playPause: togglePlayPause(); return
            case .menu:
                // Menu 状态机（v135）：面板关闭 → 呼出设置面板；面板显示中 → 放行系统默认（退出应用）。
                // 显示中时焦点在面板内，本方法收不到按键（面板 onExitCommand 负责退出）——此处只处理关闭态。
                if !DYSettingsModel.shared.isOpen {
                    DYSettingsModel.shared.openPanel()
                    return
                }
                break
            default: break
            }
        }
        super.pressesBegan(presses, with: event)
    }
}

extension DYPlayerViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        PlaybackEngine.shared.urls.count
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! PlayerCell
        cell.playerLayerView.frame = cell.contentView.bounds
        cell.coverImageView.frame = cell.contentView.bounds
        // Cell 不创建 player；willDisplay 阶段由 PlayerManager 分配绑定（此处先占位，willDisplay 再绑）
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        collectionView.bounds.size
    }
    /// willDisplay：向 PlayerManager 申请绑定对应 player + 封面兜底 + PC 版信息填充
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let c = cell as? PlayerCell else { return }
        c.playerLayerView.frame = c.contentView.bounds
        c.coverImageView.frame = c.contentView.bounds
        let idx = indexPath.item
        c.applyInfo(PlaybackEngine.shared.videoInfo(at: idx))
        // peekPlayer 纯查询不 acquire——避免快速滑动时 willDisplay 把池撑大（抖动→黑屏）
        if let p = PlayerManager.shared.peekPlayer(at: idx) {
            c.bind(player: p)
            let ready = (p.currentItem?.status == .readyToPlay)
            c.setCoverVisible(!ready)
            if !ready { loadCover(for: c, index: idx) }
        } else {
            c.setCoverVisible(true)
            loadCover(for: c, index: idx)
        }
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
}

/// SwiftUI 包装：UICollectionView 垂直分页真实视频滑动（PlayerManager 上限 3 池）。
struct NativePlayerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DYPlayerViewController {
        DYPlayerViewController()
    }
    func updateUIViewController(_ uiViewController: DYPlayerViewController, context: Context) {}
}
