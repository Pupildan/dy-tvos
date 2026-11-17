import SwiftUI
import UIKit
import AVFoundation
import AVKit

// MARK: - 直播流屏（v184 全屏纵向分页刷直播间，照抄 NativePlayerView 分页/手势/遥控/池窗口）

/// SwiftUI 包装：直播纵向分页流（全屏）。设置面板「直播」进入；Menu 关闭回播放。
/// v186：删掉右上角返回按钮——它抢焦点导致遥控上下键被 SwiftUI 焦点引擎吃掉、
/// 切不了房（真机日志实锤）。退出统一走 Menu（onExitCommand），无焦点竞争。
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

/// 可聚焦 collectionView（v186）：PlayerCell `canBecomeFocused=false`（照 VOD，避免 cell 抢焦点干扰滑动），
/// 但直播屏需要遥控上下键锚点 → 让 collectionView 自己可聚焦。聚焦后遥控上下键走 live VC 的 pressesBegan 切房，
/// 不再被 SwiftUI 焦点引擎吃掉（真机实锤：返回按钮/无可聚焦元素 → 上下键失效）。
final class DYLiveFocusCollectionView: UICollectionView {
    override var canBecomeFocused: Bool { true }
}

/// 直播单房间 cell（v188）：内嵌 AVPlayerViewController 出画面。
/// v186/v187 手动管 AVPlayerLayer 连败两轮（日志 layer=1920x1080 ready=1 playing=1 全绿却黑屏）→
/// 按铁律回退标准底座：AVPlayerViewController 自己管 AVPlayerLayer 渲染，天生出画面，绕开手动 layer 泥潭。
/// 左下角标题/观看数 overlay 照 VOD PC 版排版。播放控件关掉（上下键切房，不要自带 UI）。
final class LivePlayerCell: UICollectionViewCell {
    private let playerVC = AVPlayerViewController()
    private let nicknameLabel = UILabel()
    private let descLabel = UILabel()
    /// 当前绑定的 player（供池驱逐时 pause）
    private(set) var player: AVPlayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        // AVPlayerViewController：tvOS 标准出画面方案（自带 AVPlayerLayer 渲染）
        playerVC.showsPlaybackControls = false
        playerVC.videoGravity = .resizeAspect
        // ⚠️ tvOS 上 AVPlayerViewController.view 是 UIView?（iOS 非可选）——必须解包，否则编译错
        guard let pv = playerVC.view else { return }
        pv.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pv)
        NSLayoutConstraint.activate([
            pv.topAnchor.constraint(equalTo: contentView.topAnchor),
            pv.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            pv.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pv.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        // 左下信息区（照 VOD PC 版：@主播·X观看 / 标题）
        nicknameLabel.font = .boldSystemFont(ofSize: 32)
        nicknameLabel.textColor = .white
        nicknameLabel.shadowColor = .black
        nicknameLabel.shadowOffset = CGSize(width: 1, height: 1)
        descLabel.font = .systemFont(ofSize: 26, weight: .medium)
        descLabel.textColor = .white
        descLabel.shadowColor = .black
        descLabel.shadowOffset = CGSize(width: 1, height: 1)
        descLabel.numberOfLines = 2
        contentView.addSubview(nicknameLabel)
        contentView.addSubview(descLabel)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var canBecomeFocused: Bool { false }   // 照 VOD cell：排除出焦点系统，滑动不被焦点干扰
    override func layoutSubviews() {
        super.layoutSubviews()
        let b = contentView.bounds
        let infoLeft: CGFloat = 24
        let infoBottom: CGFloat = 44
        let infoW = b.width - infoLeft * 2
        descLabel.frame = CGRect(x: infoLeft, y: b.height - infoBottom - 62, width: infoW, height: 62)
        nicknameLabel.frame = CGRect(x: infoLeft, y: b.height - infoBottom - 62 - 4 - 40, width: infoW, height: 40)
    }

    /// 绑 player（AVPlayerViewController 自己 render）+ 填标题/观看数
    func configure(room: DYLiveRoom, player: AVPlayer, viewerText: String) {
        self.player = player
        playerVC.player = player
        let nick = room.ownerName.isEmpty ? "" : "@\(room.ownerName)"
        let time = viewerText
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
        descLabel.text = room.title.isEmpty ? nil : room.title
    }
    /// 离屏解绑（池仍持有 player，回滚回来 configure 重绑）
    func unbind() {
        playerVC.player = nil
        player = nil
    }
    /// 重绑 player（updatePlaybackStates 每 tick 调；标题/观看数已由 configure 填过，这里只换 player）
    func bind(player: AVPlayer) {
        self.player = player
        playerVC.player = player
    }
    private static let textShadow: NSShadow = {
        let s = NSShadow()
        s.shadowColor = UIColor.black
        s.shadowOffset = CGSize(width: 1, height: 1)
        s.shadowBlurRadius = 2
        return s
    }()
}

/// 直播纵向分页控制器（照抄 DYPlayerViewController 的分页/snap/pan 护栏/遥控，但数据走 DYLiveClient
/// 游标翻页、拉流走 HLS 单房间池）。池窗口 [idx-1, idx+1]，相邻房间预 resolve HLS 预取。
final class DYLiveFeedViewController: UIViewController {
    private var collectionView: UICollectionView!
    private var currentIndex = 0
    private var didInitialScroll = false

    // MARK: 直播单房间 HLS 池（窗口 [idx-1, idx+1]；驱逐只 pause 不销毁，player 按 webRid 缓存）
    private var players: [Int: AVPlayer] = [:]
    /// player 缓存（webRid → AVPlayer）：驱逐只 pause 不销毁，刷回来复用已缓冲 player 秒出画面
    /// （v189 铁证：同房间 player 被反复销毁重建 idx=0 出现 3 次 → 每次重缓冲黑屏。缓存修之）
    private var playerCache: [String: AVPlayer] = [:]
    /// 缓存顺序（webRid，用于超上限淘汰最旧）
    private var playerCacheOrder: [String] = []
    private let playerCacheLimit = 8
    private var hlsCache: [String: String] = [:]        // webRid → 已 resolve 的 HLS URL
    private var resolving = Set<String>()               // webRid → enter 在飞去重
    private var playerRequests: [Int: String] = [:]     // index → 发起时的 webRid（防竞态）
    /// KVO ready 观察（照 VOD readyObservers）：player status → readyToPlay 时补 play（修"没画面只有声音"）
    private var readyObservers: [Int: NSKeyValueObservation] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collectionView = DYLiveFocusCollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.register(LivePlayerCell.self, forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.backgroundColor = .black
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

    /// 遥控焦点锚点：初始焦点落 collectionView → 上下键进 pressesBegan 切房（照 NativePlayerView）
    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        return [collectionView]
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
        // 焦点屏护栏（照 v171）：面板/浏览屏打开时滑动交焦点引擎
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
        // setContentOffset 替代 scrollToItem（后者 flow layout 未就绪抛 NSException，.ips 实锤）
        let pageHeight = max(1, collectionView.bounds.height)
        let maxOffset = max(0, collectionView.contentSize.height - collectionView.bounds.height)
        let targetY = min(CGFloat(clamped) * pageHeight, maxOffset)
        collectionView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
        currentIndex = clamped
        prepareWindow(center: clamped)
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

    // MARK: 池窗口（窗口 [idx-1, idx+1]；驱逐只 pause 不销毁，player 按 webRid 缓存供刷回复用）
    private func prepareWindow(center idx: Int) {
        let rooms = DYLiveClient.shared.rooms
        guard rooms.indices.contains(idx) else { return }
        // 窗口外：只 pause 不销毁（player 留在 playerCache，刷回来复用已缓冲的秒出画面）
        // v189 铁证：旧版 replaceCurrentItem(nil)+删除 → 刷回来 createPlayer 重建重缓冲 → 黑屏（有声音）
        for (i, p) in players where abs(i - idx) > 1 {
            readyObservers[i]?.invalidate()
            readyObservers.removeValue(forKey: i)
            p.pause()
            players.removeValue(forKey: i)
            playerRequests.removeValue(forKey: i)
        }
        // 窗口内 ensure
        for i in [idx - 1, idx, idx + 1] where rooms.indices.contains(i) {
            ensurePlayer(index: i, room: rooms[i])
        }
    }

    /// ensure 房间 player：先查 playerCache(webRid) 复用 → 查 HLS 缓存建 → enter resolve 后建（异步）
    private func ensurePlayer(index: Int, room: DYLiveRoom) {
        if players[index] != nil { return }
        let reqId = room.webRid
        playerRequests[index] = reqId
        // v190：先查 playerCache——刷回来复用已缓冲的 player 秒出画面，不再销毁重建重缓冲（v189 黑屏根因）
        if let cached = playerCache[reqId] {
            players[index] = cached
            // 重新挂 ready 观察（驱逐时 invalidate 了）
            readyObservers[index] = cached.observe(\.currentItem?.status, options: [.new]) { [weak self] player, _ in
                guard let self else { return }
                DispatchQueue.main.async {
                    guard player.currentItem?.status == .readyToPlay else { return }
                    self.updatePlaybackStates(center: self.currentIndex)
                }
            }
            DYLog.shared.log("LIVEFEED reuse cache idx=\(index) webRid=\(reqId)")
            return
        }
        // 已 resolve 的 HLS 直接建 player（相邻预取命中缓存秒建）
        if let hls = hlsCache[room.webRid] {
            createPlayer(index: index, url: hls)
            return
        }
        // feed 阶段已带 hls（偶发）直接用
        let feedHls = DYLiveClient.bestHlsUrl(room.hlsUrls)
        if !feedHls.isEmpty {
            hlsCache[room.webRid] = feedHls
            createPlayer(index: index, url: feedHls)
            return
        }
        // enter resolve（去重防并发）
        guard !resolving.contains(room.webRid) else { return }
        resolving.insert(room.webRid)
        DYLog.shared.log("LIVEFEED resolve idx=\(index) webRid=\(room.webRid)")
        DYLiveClient.shared.enterRoom(room.webRid) { [weak self] entered in
            guard let self else { return }
            self.resolving.remove(room.webRid)
            guard let entered else {
                DYLog.shared.event("LIVEFEED resolve fail idx=\(index) webRid=\(room.webRid)")
                return
            }
            let hls = DYLiveClient.bestHlsUrl(entered.hlsUrls)
            guard !hls.isEmpty else {
                DYLog.shared.event("LIVEFEED resolve no-hls idx=\(index) webRid=\(room.webRid)")
                return
            }
            self.hlsCache[room.webRid] = hls
            // 仅当该 index 仍指向同一房间且还在窗口才建（防快速滑动竞态）
            let rooms = DYLiveClient.shared.rooms
            guard self.playerRequests[index] == reqId,
                  rooms.indices.contains(index), rooms[index].webRid == reqId else { return }
            self.createPlayer(index: index, url: hls)
            self.updatePlaybackStates(center: self.currentIndex)
        }
    }

    private func createPlayer(index: Int, url: String) {
        guard let u = URL(string: url) else { return }
        let item = AVPlayerItem(url: u)
        let p = AVPlayer(playerItem: item)
        players[index] = p
        // 存进 playerCache（webRid 键）——驱逐只 pause 不销毁，刷回来复用已缓冲 player 秒出画面
        let reqId = playerRequests[index] ?? ""
        if !reqId.isEmpty {
            if playerCache[reqId] == nil {
                playerCacheOrder.append(reqId)
            }
            playerCache[reqId] = p
            evictPlayerCacheIfNeeded()
        }
        // KVO ready 观察（照 VOD PlayerManager.readyObservers）：status 异步变 readyToPlay 时补 play
        readyObservers[index] = p.observe(\.currentItem?.status, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                guard player.currentItem?.status == .readyToPlay else { return }
                self.updatePlaybackStates(center: self.currentIndex)
            }
        }
        DYLog.shared.log("LIVEFEED player idx=\(index) hls=\(url.prefix(70))")
        DispatchQueue.main.async { [weak self] in
            self?.updatePlaybackStates(center: self?.currentIndex ?? index)
        }
    }

    /// player 缓存超上限：淘汰最旧且不在当前窗口的（释放解码器，防内存涨）
    private func evictPlayerCacheIfNeeded() {
        guard playerCacheOrder.count > playerCacheLimit else { return }
        let windowRids = Set(DYLiveClient.shared.rooms.enumerated()
            .filter { abs($0.offset - currentIndex) <= 1 }.map { $0.element.webRid })
        // 从最旧往新找第一个不在窗口的淘汰
        for i in 0..<playerCacheOrder.count {
            let rid = playerCacheOrder[i]
            guard !windowRids.contains(rid), let p = playerCache[rid] else { continue }
            p.pause()
            p.replaceCurrentItem(with: nil)
            playerCache.removeValue(forKey: rid)
            playerCacheOrder.remove(at: i)
            DYLog.shared.log("LIVEFEED cache evict webRid=\(rid) left=\(playerCacheOrder.count)")
            return
        }
    }

    /// 居中播放，非居中暂停（AVPlayerViewController 自己 render 出画面，cell 只 bind + play/pause）
    private func updatePlaybackStates(center index: Int) {
        for cell in collectionView.visibleCells {
            guard let c = cell as? LivePlayerCell,
                  let ip = collectionView.indexPath(for: c) else { continue }
            let idx = ip.item
            let isCenter = (idx == index)
            if let p = players[idx] {
                c.bind(player: p)
                let ready = (p.currentItem?.status == .readyToPlay)
                if isCenter {
                    if ready {
                        if p.timeControlStatus != .playing { p.play() }
                    } else {
                        // ready 后 KVO readyObservers 会再触发本方法补 play
                        p.pause()
                    }
                    DYLog.shared.log("LIVEFEED state idx=\(idx) ready=\(ready ? 1 : 0) playing=\(p.timeControlStatus == .playing ? 1 : 0) status=\(p.currentItem?.status.rawValue ?? -1)")
                } else {
                    p.pause()
                }
            }
        }
    }

    private func loadMoreIfNeeded() {
        guard !DYLiveClient.shared.isLoadingMore else { return }
        DYLiveClient.shared.loadMore { [weak self] fresh in
            guard let self, !fresh.isEmpty else { return }
            self.collectionView.reloadData()
            // 翻页追加后无需滚动手动对齐（cell 复用按 index，contentOffset 不变）
            self.updatePlaybackStates(center: self.currentIndex)
        }
    }

    // MARK: 遥控（照 NativePlayerView pressesBegan：上下切房，Menu 关闭走 SwiftUI onExitCommand）
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // 焦点屏护栏：其他屏打开时按键交 SwiftUI 焦点引擎（照 v171）
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
}

extension DYLiveFeedViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        DYLiveClient.shared.rooms.count
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! LivePlayerCell
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        collectionView.bounds.size
    }
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let c = cell as? LivePlayerCell else { return }
        let idx = indexPath.item
        let rooms = DYLiveClient.shared.rooms
        guard rooms.indices.contains(idx) else { return }
        let room = rooms[idx]
        // peekPlayer 语义：已建则绑，未建不 acquire（防快速滑动撑大池）
        // AVPlayerViewController 自己 render 出画面（v186/v187 手动 AVPlayerLayer 连败两轮的黑屏根因绕开）
        if let p = players[idx] {
            let ready = (p.currentItem?.status == .readyToPlay)
            c.configure(room: room, player: p, viewerText: room.userCount.isEmpty ? "" : "\(room.userCount)观看")
            DYLog.shared.log("LIVEFEED willDisplay idx=\(idx) ready=\(ready ? 1 : 0) status=\(p.currentItem?.status.rawValue ?? -1)")
        }
    }
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // 离屏 cell 解绑 player（池仍持有，回滚回来 willDisplay 重绑）
        (cell as? LivePlayerCell)?.unbind()
    }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, withTargetContentOffset targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let pageHeight = max(1, scrollView.bounds.height)
        let targetY = targetContentOffset.pointee.y
        let snappedY = (velocity.y >= 0 ? ceil(targetY / pageHeight) : floor(targetY / pageHeight)) * pageHeight
        targetContentOffset.pointee.y = snappedY
    }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updatePlaybackStates(center: centeredIndex())
        if !didInitialScroll {
            didInitialScroll = true
            prepareWindow(center: currentIndex)
        }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updatePlaybackStates(center: centeredIndex())
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didInitialScroll, !DYLiveClient.shared.rooms.isEmpty, collectionView.bounds.height > 0 {
            didInitialScroll = true
            let idx = min(currentIndex, DYLiveClient.shared.rooms.count - 1)
            currentIndex = idx
            scrollTo(index: idx, animated: false)
            // 焦点落到 collectionView → 遥控上下键进 pressesBegan 切房 + updatePlaybackStates 正常播放
            DispatchQueue.main.async { [weak self] in
                self?.view.window?.updateFocusIfNeeded()
            }
        }
    }
}
