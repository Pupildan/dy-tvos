import SwiftUI
import AVFoundation
import AVKit

// MARK: - AVPlayer 包装（直播 HLS 播放，复用 PlayerLayerView）

/// 把 PlayerLayerView（AVPlayerLayer）包成 SwiftUI view。player 由外部 DYLivePlayerController 持有。
struct DYLivePlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.player = player
        v.playerLayer.videoGravity = .resizeAspect
        return v
    }
    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}
}

// MARK: - 直播浏览屏（设置面板「直播」进入；网格选房 → 进播放屏）

/// 直播浏览屏（第一版）：web /webcast/feed/ 热门直播间网格，选中 → DYLivePlayerScreen。
/// 照抄 DYMixScreen/DYCommentScreen 骨架：常驻「返回播放」可聚焦按钮（v148 焦点铁律）+ onExitCommand 关闭。
struct DYLiveBrowseScreen: View {
    @ObservedObject var model = DYQuickPanelModel.shared
    @FocusState private var focused: String?
    @State private var rooms: [DYLiveRoom] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var selectedRoom: DYLiveRoom?

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            HStack {
                Spacer(minLength: 0)
                panel
                    .frame(width: 1040)
                    .padding(.trailing, 32)
                    .padding(.vertical, 40)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            focused = "close"
            DYLiveClient.shared.fetchLiveFeed { list in
                rooms = list
                failed = list.isEmpty
                if focused == nil || focused == "close" {
                    focused = list.first.map { "room-\($0.webRid)" } ?? "close"
                }
            }
        }
        .onExitCommand { model.isLiveOpen = false }
        .transition(.opacity)
        // 进房播放（全屏覆盖，zIndex 更高）
        .overlay {
            if let room = selectedRoom {
                DYLivePlayerScreen(room: room) { selectedRoom = nil }
                    .transition(.opacity)
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("直播 · 热门")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                Button {
                    model.isLiveOpen = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("返回播放")
                    }
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background {
                        if focused == "close" {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white, lineWidth: 4)
                        }
                    }
                }
                .buttonStyle(PanelRowButtonStyle())
                .focused($focused, equals: "close")
            }
            if !rooms.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 18) {
                        ForEach(rooms, id: \.webRid) { room in
                            roomCell(room)
                        }
                    }
                    .padding(.top, 4)
                }
            } else if failed {
                Text("直播列表获取失败（日志 LIVE 行有详情），请稍后重试")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 40)
            } else {
                Text("直播列表加载中…")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 40)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .background(livePanelBackground)
    }

    /// 直播间单元：封面 16:9 + 标题 + 主播 + 观看数 + 聚焦白描边（照抄 workCell 样式）
    private func roomCell(_ room: DYLiveRoom) -> some View {
        Button {
            focused = "room-\(room.webRid)"
            DYLog.shared.event("LIVE select webRid=\(room.webRid) title=\(room.title.prefix(20))")
            selectedRoom = room
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if !room.coverUrl.isEmpty, let cu = URL(string: room.coverUrl) {
                        AvatarImage(url: cu)
                    } else {
                        Color.white.opacity(0.1)
                    }
                    // 直播角标 + 观看数
                    VStack {
                        HStack {
                            Text("直播中")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
                            Spacer()
                        }
                        .padding(6)
                        Spacer()
                        HStack {
                            Spacer()
                            if !room.userCount.isEmpty {
                                Label(room.userCount, systemImage: "eye")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                        .padding(6)
                    }
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(room.title.isEmpty ? "（无标题）" : room.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                if !room.ownerName.isEmpty {
                    Text(room.ownerName)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .background {
                if focused == "room-\(room.webRid)" {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 4)
                        .padding(-6)
                }
            }
        }
        .buttonStyle(PanelRowButtonStyle())
        .focused($focused, equals: "room-\(room.webRid)")
    }

    /// 液态玻璃背景（tvOS 26 glassEffect；低版本 ultraThinMaterial 回退，照抄 DYMixScreen）
    @ViewBuilder
    private var livePanelBackground: some View {
        if #available(tvOS 26.0, *) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.clear)
                .glassEffect(.regular.tint(.black.opacity(0.35)), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        }
    }
}

// MARK: - 直播播放屏（单房间 AVPlayer HLS，全屏；Menu 关闭回浏览）

/// 直播播放屏（第一版：匿名 HLS 拉流，无弹幕）。进房取 hls_pull_url_map → AVPlayer 播 .m3u8。
/// 单房间独立 AVPlayer，不进 PlayerManager 池（池是 feed 索引驱动，硬塞会打架）。
struct DYLivePlayerScreen: View {
    let room: DYLiveRoom
    var onClose: () -> Void
    @FocusState private var focused: Bool
    @State private var player: AVPlayer?
    @State private var statusText = "进房中…"
    @State private var failed = false
    /// 自动隐藏的返回按钮（播放后 3s 淡出，按 Menu/任意键唤出——第一版简化：常驻右上角）
    private let controller = DYLivePlayerController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                DYLivePlayerLayerView(player: player)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    if failed {
                        Text("直播拉流失败（日志 LIVE 行有详情）")
                            .font(.system(size: 26))
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        ProgressView().scaleEffect(1.6)
                        Text(statusText)
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            // 右上角返回 + 标题
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(room.title.isEmpty ? "直播" : room.title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if !room.ownerName.isEmpty {
                            Text(room.ownerName + (room.userCount.isEmpty ? "" : " · \(room.userCount)人观看"))
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    Spacer(minLength: 0)
                    Button {
                        controller.stop()
                        onClose()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            if focused {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white, lineWidth: 4)
                            }
                        }
                    }
                    .buttonStyle(PanelRowButtonStyle())
                    .focused($focused)
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                Spacer()
            }
        }
        .onAppear {
            focused = true   // 常驻可聚焦返回按钮（v148 焦点铁律）
            loadStream()
        }
        .onExitCommand {
            controller.stop()
            onClose()
        }
        .onDisappear { controller.stop() }
        .transition(.opacity)
    }

    private func loadStream() {
        DYLiveClient.shared.enterRoom(room.webRid) { entered in
            guard let entered, !entered.hlsUrls.isEmpty else {
                // enter 失败但 feed 阶段可能已带 hls（罕见），兜底用 room 自己的
                let fallback = DYLiveClient.bestHlsUrl(room.hlsUrls)
                guard !fallback.isEmpty else {
                    failed = true
                    statusText = "该直播间暂无可用拉流地址"
                    return
                }
                startPlayer(url: fallback)
                return
            }
            let hls = DYLiveClient.bestHlsUrl(entered.hlsUrls)
            guard !hls.isEmpty else {
                failed = true
                statusText = "该直播间暂无 HLS 拉流地址"
                return
            }
            startPlayer(url: hls)
        }
    }

    private func startPlayer(url: String) {
        guard let u = URL(string: url) else {
            failed = true
            statusText = "拉流地址解析失败"
            return
        }
        statusText = "连接直播流…"
        let item = AVPlayerItem(url: u)
        let p = AVPlayer(playerItem: item)
        player = p
        controller.attach(p)
        p.play()
        DYLog.shared.event("LIVE play webRid=\(room.webRid) hls=\(url.prefix(80))")
    }
}

/// 直播播放器生命周期管理（stop 时暂停并释放 item，防后台续流）。
final class DYLivePlayerController {
    private var player: AVPlayer?
    func attach(_ p: AVPlayer) { player = p }
    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        DYLog.shared.log("LIVE player stop")
    }
}
