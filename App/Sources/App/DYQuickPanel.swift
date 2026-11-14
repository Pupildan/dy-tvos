import SwiftUI

/// 快捷悬浮窗状态（v145：播放中按 OK 呼出，屏幕中下；OK 再按=关闭；面板内 Menu=关闭回播放）。
final class DYQuickPanelModel: ObservableObject {
    static let shared = DYQuickPanelModel()

    @Published var isOpen = false
    /// 当前视频信息（主页头像/合集条件显示）
    @Published var info: DYVideoInfo?
    /// 不感兴趣动作（控制器接线：跳过当前视频）
    var onDislike: (() -> Void)?

    /// OK 呼出/关闭切换（控制器 pressesBegan 调用；面板打开时焦点在面板内，OK=选中项目不回控制器）
    func toggle() {
        isOpen.toggle()
        DYLog.shared.event("QUICK panel \(isOpen ? "open" : "close") (ok)")
    }

    func open(info: DYVideoInfo?) {
        self.info = info
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

    func selectComment() {
        noteAndClose("comment")
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
        .transition(.opacity.combined(with: .scale(scaleEffect: 0.92, anchor: .bottom)))
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
