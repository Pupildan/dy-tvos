import SwiftUI

/// 快捷悬浮窗状态（v145：播放中按确认键呼出，屏幕中下；OK 再按=关闭；面板内 Menu=关闭回播放）。
final class DYQuickPanelModel: ObservableObject {
    static let shared = DYQuickPanelModel()

    @Published var isOpen = false
    /// 评论屏开关（v147：快捷面板「评论」项打开）
    @Published var isCommentOpen = false
    /// 面板对应的视频 id（评论请求用）
    var awemeId = ""
    /// 当前视频信息（主页头像/合集条件显示）
    @Published var info: DYVideoInfo?
    /// 不感兴趣动作（控制器接线：跳过当前视频）
    var onDislike: (() -> Void)?

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

    func selectHome() {
        noteAndClose("home")
    }

    /// 评论：关闭快捷面板 + 打开评论屏（评论屏自身 Menu 关闭）
    func selectComment() {
        isOpen = false
        isCommentOpen = true
        DYLog.shared.event("QUICK select comment id=\(awemeId)")
    }

    func selectMix() {
        noteAndClose("mix")
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

/// 快捷悬浮窗（屏幕中下）：液态玻璃（tvOS 26 glassEffect；低版本 ultraThinMaterial 回退）。
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
                .frame(width: 620, height: model.info?.isMix == true ? 380 : 300)
                .padding(.bottom, 90)
        }
        .onAppear { focusedRow = .home }
        .onExitCommand { model.close() }   // 面板内 Menu=关闭回播放（不退出应用）
        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            quickRow(row: .home, icon: "avatar", title: "主页", subtitle: "查看作者全部作品")
            quickRow(row: .comment, icon: "bubble.left.and.bubble.right.fill", title: "评论", subtitle: "查看视频评论")
            if model.info?.isMix == true {
                quickRow(row: .mix, icon: "square.stack.3d.up.fill", title: "合集", subtitle: model.info?.mixName ?? "查看合集内容")
            }
            quickRow(row: .dislike, icon: "hand.thumbsdown.fill", title: "不感兴趣", subtitle: "不再推送类似内容")
        }
        .padding(24)
        .background(panelBackground)
    }

    private var panelBackground: some View {
        Group {
            if #available(tvOS 26.0, *) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(.regular.tint(.black.opacity(0.4)), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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

    private func quickRow(row: QuickRow, icon: String, title: String, subtitle: String) -> some View {
        let focused = focusedRow == row
        return Button {
            switch row {
            case .home: model.selectHome()
            case .comment: model.selectComment()
            case .mix: model.selectMix()
            case .dislike: model.selectDislike()
            }
        } label: {
            HStack(spacing: 18) {
                rowIcon(icon)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background {
                if focused {
                    if #available(tvOS 26.0, *) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.clear)
                            .glassEffect(.regular.tint(.white.opacity(0.10)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white, lineWidth: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white, lineWidth: 4))
                    }
                }
            }
            .scaleEffect(focused ? 1.04 : 1.0)
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
struct DYCommentScreen: View {
    @ObservedObject var model = DYQuickPanelModel.shared
    @State private var comments: [DYCommentItem] = []
    @State private var loaded = false
    @State private var loading = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
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
            DYCommentClient.shared.comments(for: model.awemeId, pages: 3) { items in
                comments = items
                loading = false
            }
        }
        .onExitCommand { model.isCommentOpen = false }   // Menu 关闭回播放
        .transition(.opacity)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("评论")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
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
                            HStack(alignment: .top, spacing: 14) {
                                AvatarImage(url: URL(string: c.avatarUrl) ?? URL(fileURLWithPath: "/dev/null"))
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
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .background(panelBackground)
    }

    private var panelBackground: some View {
        Group {
            if #available(tvOS 26.0, *) {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(.regular.tint(.black.opacity(0.4)), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }
}
