import SwiftUI

/// 快捷悬浮窗状态（v145：播放中按确认键呼出，屏幕中下；OK 再按=关闭；面板内 Menu=关闭回播放）。
final class DYQuickPanelModel: ObservableObject {
    static let shared = DYQuickPanelModel()

    @Published var isOpen = false
    /// 评论屏开关（v147：快捷面板「评论」项打开）
    @Published var isCommentOpen = false
    /// 作者主页屏开关（v153：主页项打开；作品列表接口仍被风控，先展示资料）
    @Published var isProfileOpen = false
    /// 主页对应的作者 sec_uid
    @Published var profileSecUid = ""
    /// 面板对应的视频 id（评论请求用）
    var awemeId = ""
    /// 当前视频信息（主页头像/合集条件显示）
    @Published var info: DYVideoInfo?
    /// 不感兴趣动作（控制器接线：跳过当前视频）
    var onDislike: (() -> Void)?
    /// 轻提示（主页/合集等占位动作的可见反馈；2.5s 自动消失）
    @Published var toast: String?
    private var toastTimer: Timer?

    func showToast(_ text: String) {
        toast = text
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.toast = nil
        }
    }

    /// OK 呼出/关闭切换（控制器 pressesBegan 调用；面板打开时焦点在面板内，OK=选中项目不回控制器）
    func toggle() {
        isOpen.toggle()
        DYLog.shared.event("QUICK panel \(isOpen ? "open" : "close") (ok)")
    }

    func open(info: DYVideoInfo?, awemeId: String) {
        self.info = info
        self.awemeId = awemeId
        isOpen = true
        DYLog.shared.event("QUICK panel open (ok) mix=\(info?.isMix == true ? 1 : 0)")
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        DYLog.shared.log("QUICK panel close")
    }

    /// 主页：关闭面板 → 0.4s 后开作者资料屏（事务分离防焦点异常，同评论屏 v148 模式）
    func selectHome() {
        guard let sec = info?.secUid, !sec.isEmpty else {
            noteAndClose("home")
            showToast("该视频没有作者主页信息")
            return
        }
        isOpen = false
        profileSecUid = sec
        DYLog.shared.event("QUICK select home sec=\(sec)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.isProfileOpen = true
        }
    }

    /// 评论：关闭快捷面板 → 0.4s 后再开评论屏。
    /// v148 闪退修复：真机日志实锤「select comment → ROOT auto-start」——同一 SwiftUI 事务里
    /// 移除含聚焦按钮的面板 + 插入无可聚焦元素的评论屏，tvOS 焦点引擎找不到焦点目标抛异常。
    /// 拆成两个事务（面板先关闭，焦点更新走已验证的关闭路径），评论屏自身也加了可聚焦元素。
    func selectComment() {
        isOpen = false
        DYLog.shared.event("QUICK select comment id=\(awemeId)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.isCommentOpen = true
        }
    }

    func selectMix() {
        noteAndClose("mix")
        showToast("合集浏览需登录支持，登录功能即将上线")
    }

    /// 不感兴趣：跳过当前视频（后续版本接反馈 API 不再推送同类）
    func selectDislike() {
        DYLog.shared.event("QUICK dislike -> skip")
        isOpen = false
        onDislike?()
    }

    private func noteAndClose(_ name: String) {
        DYLog.shared.event("QUICK select \(name) (待实施)")
        isOpen = false
    }
}

/// 快捷悬浮窗（v148：屏幕底部居中、选项横向卡片排列）：液态玻璃（tvOS 26 glassEffect；低版本 ultraThinMaterial 回退）。
/// 项目：主页（博主头像图标）/ 评论 / 合集（仅合集内容显示）/ 不感兴趣。
struct DYQuickPanelView: View {
    @ObservedObject var model = DYQuickPanelModel.shared
    @FocusState private var focusedRow: QuickRow?

    enum QuickRow: Hashable {
        case home, comment, mix, dislike
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            panel
                .padding(.bottom, 90)
        }
        // v149 关键：撑满全宽再水平居中——RootView 的 ZStack 是 alignment: .leading，
        // VStack 只包内容宽时会被钉在屏幕左侧（v145-v148「位置不对」的真凶）
        .frame(maxWidth: .infinity)
        .onAppear { focusedRow = .home }
        .onExitCommand { model.close() }   // 面板内 Menu=关闭回播放（不退出应用）
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
    }

    private var panel: some View {
        HStack(spacing: 16) {
            quickCard(row: .home, icon: "avatar", title: "主页")
            quickCard(row: .comment, icon: "bubble.left.and.bubble.right.fill", title: "评论")
            if model.info?.isMix == true {
                quickCard(row: .mix, icon: "square.stack.3d.up.fill", title: "合集")
            }
            quickCard(row: .dislike, icon: "hand.thumbsdown.fill", title: "不感兴趣")
        }
        .padding(18)
        .background(panelBackground)
    }

    /// v149：tvOS 26 标准液态玻璃（无黑色 tint——用户要求透出背后的视频）
    private var panelBackground: some View {
        Group {
            if #available(tvOS 26.0, *) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }

    @ViewBuilder
    private func rowIcon(_ kind: String) -> some View {
        if kind == "avatar", let urlStr = model.info?.avatarUrl, let url = URL(string: urlStr) {
            AvatarImage(url: url)
                .frame(width: 52, height: 52)
                .clipShape(Circle())
        } else {
            Image(systemName: kind == "avatar" ? "person.circle.fill" : kind)
                .font(.system(size: 40))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
        }
    }

    /// v148：横向紧凑卡片（图标上/文字下），焦点=白描边+放大，左右键移动焦点（SwiftUI 焦点链自动）。
    private func quickCard(row: QuickRow, icon: String, title: String) -> some View {
        let focused = focusedRow == row
        return Button {
            switch row {
            case .home: model.selectHome()
            case .comment: model.selectComment()
            case .mix: model.selectMix()
            case .dislike: model.selectDislike()
            }
        } label: {
            VStack(spacing: 12) {
                rowIcon(icon)
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(width: 210, height: 150)
            .background {
                if focused {
                    if #available(tvOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.clear)
                            .glassEffect(.regular.tint(.white.opacity(0.10)), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white, lineWidth: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white, lineWidth: 4))
                    }
                }
            }
            .scaleEffect(focused ? 1.05 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: focused)
        }
        .buttonStyle(PanelRowButtonStyle())
        .focused($focusedRow, equals: row)
    }
}

/// 头像异步图（SwiftUI 用，AvatarLoader 记忆化）。
struct AvatarImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable()
            } else {
                Color.white.opacity(0.15)
            }
        }
        .onAppear {
            guard image == nil else { return }
            AvatarLoader.shared.load(url) { img in image = img }
        }
    }
}

/// 评论屏（v147：快捷面板「评论」打开；全屏液态玻璃列表；Menu 关闭回播放）。
/// 数据：DYCommentClient 3 页 60 条起步；Menu=关闭。
/// v148 焦点修复：评论行改可聚焦 Button + 常驻「返回播放」按钮——tvOS 焦点环境
/// 必须时刻有可聚焦元素（否则真机闪退，v147 实锤）；数据到达后焦点自动落到首条评论。
struct DYCommentScreen: View {
    @ObservedObject var model = DYQuickPanelModel.shared
    @FocusState private var focusedItem: String?
    @State private var comments: [DYCommentItem] = []
    @State private var loaded = false
    @State private var loading = false

    var body: some View {
        ZStack {
            // v149：黑幕减淡（0.75→0.35）——标准液态玻璃要透出背后的视频
            Color.black.opacity(0.35).ignoresSafeArea()
            HStack {
                Spacer(minLength: 0)
                list
                    .frame(width: 760)
                    .padding(.trailing, 32)
                    .padding(.vertical, 40)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            loading = true
            focusedItem = "close"
            DYCommentClient.shared.comments(for: model.awemeId, pages: 3) { items in
                comments = items
                loading = false
                if focusedItem == nil || focusedItem == "close" {
                    focusedItem = items.first?.cid ?? "close"
                }
            }
        }
        .onExitCommand { model.isCommentOpen = false }   // Menu 关闭回播放
        .transition(.opacity)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("评论")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                Button {
                    model.isCommentOpen = false
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
                        if focusedItem == "close" {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white, lineWidth: 4)
                        }
                    }
                }
                .buttonStyle(PanelRowButtonStyle())
                .focused($focusedItem, equals: "close")
            }
            if loading && comments.isEmpty {
                Text("加载中...")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 40)
            } else if comments.isEmpty {
                Text("还没有评论")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 40)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(comments, id: \.cid) { c in
                            Button { } label: {
                                commentRow(c)
                            }
                            .buttonStyle(PanelRowButtonStyle())
                            .focused($focusedItem, equals: c.cid)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .background(panelBackground)
    }

    private func commentRow(_ c: DYCommentItem) -> some View {
        let focused = focusedItem == c.cid
        return HStack(alignment: .top, spacing: 14) {
            Group {
                if !c.avatarUrl.isEmpty, let url = URL(string: c.avatarUrl) {
                    AvatarImage(url: url)
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 46))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(c.nickname.isEmpty ? "抖音用户" : c.nickname)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    if !c.createTimeText.isEmpty {
                        Text(c.createTimeText)
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                Text(c.text)
                    .font(.system(size: 25))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if c.digg > 0 {
                    Text("👍 " + String(c.digg))
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
        }
        .padding(14)
        .background {
            if focused {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white, lineWidth: 4))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07))
            }
        }
    }

    /// v149：标准液态玻璃无 tint（透出视频），与快捷面板一致
    private var panelBackground: some View {
        Group {
            if #available(tvOS 26.0, *) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }
}

/// 作者主页屏（v153：快捷面板「主页」打开；user/profile/other 匿名已通）。
/// 焦点规则：常驻可聚焦元素（返回按钮）；Menu 关闭回播放。
struct DYProfileScreen: View {
    @ObservedObject var model = DYQuickPanelModel.shared
    @FocusState private var focused: String?
    @State private var user: DYProfileUser?
    @State private var worksCount = -2   // -2=加载中 -1=空响应 0+=数据
    @State private var failed = false
    @State private var loaded = false
    /// v168 截获的作品列表（WebView 截获 aweme/post 精简数据）
    @State private var works: [DYCapturedWork] = []
    @State private var worksHasMore = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            HStack {
                Spacer(minLength: 0)
                panel
                    .frame(width: 640)
                    .padding(.trailing, 32)
                    .padding(.vertical, 40)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            focused = "close"
            let sec = model.profileSecUid
            // v166：资料+作品改吃 WebView 截获（原生 fetch 链被服务端 200 空拒，v165 日志实锤）。
            // 注册 delegate，DYWorksCapture 截到 profile/other 响应解析成 DYProfileUser 回调。
            worksCount = -2
            DYWorksCapture.shared.delegate = self
            DYWorksCapture.shared.fetch(secUid: sec)
        }
        .onExitCommand { model.isProfileOpen = false }   // Menu 关闭回播放
        .transition(.opacity)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("作者主页")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                Button {
                    model.isProfileOpen = false
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
            if let u = user {
                HStack(spacing: 18) {
                    Group {
                        if !u.avatarUrl.isEmpty, let url = URL(string: u.avatarUrl) {
                            AvatarImage(url: url)
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    .frame(width: 110, height: 110)
                    .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 8) {
                        Text(u.nickname.isEmpty ? "抖音用户" : u.nickname)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                        Text("抖音号：\(String(u.secUid.suffix(12)))")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
                HStack(spacing: 0) {
                    statCell(value: u.followerCount, label: "粉丝")
                    statCell(value: u.followingCount, label: "关注")
                    statCell(value: u.totalFavorited, label: "获赞")
                    statCell(value: u.awemeCount, label: "作品")
                }
                if !u.signature.isEmpty {
                    Text(u.signature)
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(worksNote)
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.5))
                // v168 作品网格（WebView 截获的作者作品；封面+标题，点击播放）
                if !works.isEmpty {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 16) {
                            ForEach(works, id: \.id) { w in
                                workCell(w)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            } else if failed {
                Text("获取失败（抖音连发限流），请稍后重试")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 40)
            } else {
                Text("加载中...")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.top, 40)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .background(panelBackground)
    }

    private var worksNote: String {
        if !works.isEmpty {
            return "作品 \(works.count) 件\(worksHasMore ? "（首页，滚动作者页加载更多）" : "")"
        }
        switch worksCount {
        case -2: return "作品列表：截获中…"
        case -1: return "作品列表：截获失败，请稍后重试"
        case 0: return "作品列表：该作者暂无可见作品"
        default: return "作品列表：截获中…（\(worksCount) 件）"
        }
    }

    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text(PlayerCell.cnCount(value))
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    /// v168 作品网格单元：封面(9:16) + 标题两行；图集帖标「图集」
    /// v169：⚠️ tvOS 焦点引擎要求 ScrollView 内 Button 绑 @FocusState 才能移入焦点
    /// （v168 无 .focused 绑定=焦点进不去网格、无选中效果、不可点——评论屏 v148 同款教训）
    private func workCell(_ w: DYCapturedWork) -> some View {
        Button {
            playWork(w)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if !w.coverUrl.isEmpty, let cu = URL(string: w.coverUrl) {
                        AvatarImage(url: cu)
                    } else {
                        Color.white.opacity(0.1)
                    }
                    if w.isImages {
                        Text("图集")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(6)
                    }
                    if !w.mixName.isEmpty {
                        Text("▦ \(w.mixName)")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(6)
                    }
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(w.desc.isEmpty ? "（无文案）" : w.desc)
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .top)
            }
        }
        .buttonStyle(PanelRowButtonStyle())
        .focused($focused, equals: w.id)
    }

    /// v168 点击作品 → merge 进 PlaybackEngine + 跳到该作品 + 关主页屏回播放
    private func playWork(_ w: DYCapturedWork) {
        if w.isImages {
            model.showToast("图集作品暂不支持播放")
            return
        }
        guard let best = DYFeedClient.selectBestPlayUrl(w.playUrls), let url = URL(string: best) else {
            model.showToast("作品无可用播放地址")
            return
        }
        var ids: [String] = []
        var urls: [URL] = []
        var durs: [Int] = []
        var infos: [DYVideoInfo] = []
        for item in works where !item.isImages {
            guard let b = DYFeedClient.selectBestPlayUrl(item.playUrls), let u = URL(string: b) else { continue }
            ids.append(item.id)
            urls.append(u)
            durs.append(item.durationMs)
            var info = DYVideoInfo()
            info.desc = item.desc
            info.hashtags = item.desc
            info.nickname = user?.nickname ?? ""
            info.avatarUrl = user?.avatarUrl ?? ""
            info.secUid = user?.secUid ?? ""
            info.createTimeText = DYFeedClient.formatCreateTime(UInt64(item.createTime))
            info.isMix = !item.mixName.isEmpty
            info.mixName = item.mixName
            infos.append(info)
        }
        guard !ids.isEmpty else { return }
        PlaybackEngine.shared.merge(ids: ids, urls: urls, replaceExisting: false,
                                     autoPlay: false, refresh: false,
                                     allDurations: durs, allInfos: infos)
        if let pos = PlaybackEngine.shared.urls.firstIndex(of: url) {
            PlaybackEngine.shared.index = pos
        }
        DYLog.shared.event("WORKS play aweme=\(w.id) pos=\(PlaybackEngine.shared.index)")
        model.isProfileOpen = false
    }

    private var panelBackground: some View {
        Group {
            if #available(tvOS 26.0, *) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }
}

// v166/v168：DYProfileScreen 订阅 DYWorksCapture 截获结果（WebView 截获 → 模型 → UI）。
// 回调已在主线程（DYWorksCapture 里 DispatchQueue.main.async）。
extension DYProfileScreen: DYWorksCapture.Delegate {
    func worksCaptureDidCapture(profile: DYProfileUser) {
        user = profile
        worksCount = profile.awemeCount
        failed = false
    }

    func worksCaptureDidCapture(works: [DYCapturedWork], hasMore: Bool) {
        self.works = works
        self.worksHasMore = hasMore
        if worksCount < 0 { worksCount = works.count }
    }
}
