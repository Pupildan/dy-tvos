import SwiftUI
import Combine

/// 设置面板全局状态（Menu 呼出 / 源切换 / 弹幕开关）。
/// 面板 = RootView ZStack 里的 SwiftUI 悬浮层；Menu 按键状态机在 DYPlayerViewController.pressesBegan。
final class DYSettingsModel: ObservableObject {
    static let shared = DYSettingsModel()

    /// 面板是否显示（Menu 第一次按=呼出；显示中再按 Menu=退出应用，由 onExitCommand 处理）
    @Published var isOpen = false
    /// 当前视频源（面板选中态）
    @Published var source: DYFeedSource = .mobile
    /// 弹幕开关（弹幕设置项；持久化）
    @Published var danmakuOn: Bool {
        didSet { UserDefaults.standard.set(danmakuOn, forKey: "dy_danmaku_on") }
    }

    private init() {
        danmakuOn = UserDefaults.standard.bool(forKey: "dy_danmaku_on")
        // UserDefaults.bool 默认 false——首次启动显式默认开
        if UserDefaults.standard.object(forKey: "dy_danmaku_on") == nil {
            danmakuOn = true
            UserDefaults.standard.set(true, forKey: "dy_danmaku_on")
        }
    }

    // MARK: - 3s 无操作自动隐藏（v136）

    private var lastInteraction = Date()
    private var autoHideTimer: Timer?

    /// 面板内任何操作（按键选择/焦点移动）调用：刷新无操作计时
    func noteInteraction() {
        lastInteraction = Date()
    }

    /// 面板显示时启动自动隐藏监视（3s 无操作 → 关面板）
    func startAutoHide() {
        lastInteraction = Date()
        stopAutoHide()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isOpen else { self.stopAutoHide(); return }
            if Date().timeIntervalSince(self.lastInteraction) > 3.0 {
                DYLog.shared.event("SETTINGS panel auto-hide (3s idle)")
                self.isOpen = false
                self.stopAutoHide()
            }
        }
    }

    func stopAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    /// 呼出/退出面板（Menu 按键状态机由控制器调用；显示中再按 Menu=退出应用走系统默认）
    func openPanel() {
        isOpen = true
        DYLog.shared.event("SETTINGS panel open (menu #1)")
    }

    /// 选视频源：切换 + 关面板。同源重复选 = 仅关面板。
    func selectSource(_ s: DYFeedSource) {
        source = s
        isOpen = false
        stopAutoHide()
        DanmakuOverlay.globalEnabled = danmakuOn
        if s != DYFeedClient.shared.source {
            DYFeedClient.shared.setSource(s)
        }
    }

    /// 弹幕设置：切开关（即时生效，不清播放）。
    func toggleDanmaku() {
        danmakuOn.toggle()
        DanmakuOverlay.globalEnabled = danmakuOn
        noteInteraction()
        DYLog.shared.event("SETTINGS danmaku -> \(danmakuOn ? "on" : "off")")
    }

    /// 占位项（直播/登录）：只记日志，后续版本实施。
    func placeholderTapped(_ name: String) {
        noteInteraction()
        DYLog.shared.event("SETTINGS placeholder \(name) (待实施)")
    }
}

/// 设置面板（屏幕左侧悬浮）：iOS 26 液态玻璃（tvOS 26 原生 glassEffect；低版本回退 ultraThinMaterial）。
/// 五项：移动端推荐 / 抖音精选 / 弹幕设置 / 直播(占位) / 登录(占位)。
/// v136 焦点样式：去灰底 → 焦点行白色描边 + 放大动画；3s 无操作自动隐藏。
struct SettingsPanelView: View {
    @ObservedObject var model = DYSettingsModel.shared
    @FocusState private var focusedRow: PanelRow?

    enum PanelRow: Hashable {
        case mobile, web, danmaku, live, login
    }

    var body: some View {
        HStack(alignment: .top) {
            panel
                .frame(width: 380)
                .padding(.leading, 28)
                .padding(.top, 40)
                .padding(.bottom, 40)
            Spacer(minLength: 0)
        }
        .onAppear {
            model.startAutoHide()
            focusedRow = .mobile   // 默认焦点落在第一项
        }
        .onDisappear {
            model.stopAutoHide()
        }
        .onChange(of: focusedRow) { _ in
            model.noteInteraction()   // 焦点移动也算操作
        }
        .onExitCommand {
            // 面板显示中按 Menu（返回键）= 退出应用（用户规格：第二次返回键才退出）
            DYLog.shared.event("SETTINGS panel exit-app (menu #2)")
            exit(0)
        }
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设置")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 6)

            sourceRow(title: "移动端推荐", subtitle: "手机端视频源", target: .mobile, row: .mobile)
            sourceRow(title: "抖音精选", subtitle: "电脑端视频源", target: .web, row: .web)
            danmakuRow
            placeholderRow(title: "直播", subtitle: "即将上线", row: .live)
            placeholderRow(title: "登录", subtitle: "即将上线", row: .login)

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(panelBackground)
    }

    /// 液态玻璃背景：tvOS 26 原生 glassEffect；低版本 ultraThinMaterial 回退
    @ViewBuilder
    private var panelBackground: some View {
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

    private func sourceRow(title: String, subtitle: String, target: DYFeedSource, row: PanelRow) -> some View {
        Button {
            model.selectSource(target)
        } label: {
            rowContent(title: title, subtitle: subtitle,
                       badge: (model.source == target ? "当前" : nil),
                       focused: focusedRow == row)
        }
        .buttonStyle(.plain)
        .focused($focusedRow, equals: row)
    }

    private var danmakuRow: some View {
        Button {
            model.toggleDanmaku()
        } label: {
            rowContent(title: "弹幕设置", subtitle: model.danmakuOn ? "开启中（按 OK 关闭）" : "已关闭（按 OK 开启）",
                       badge: model.danmakuOn ? "开" : "关",
                       focused: focusedRow == .danmaku)
        }
        .buttonStyle(.plain)
        .focused($focusedRow, equals: .danmaku)
    }

    private func placeholderRow(title: String, subtitle: String, row: PanelRow) -> some View {
        Button {
            model.placeholderTapped(title)
        } label: {
            rowContent(title: title, subtitle: subtitle, badge: "待上线", focused: focusedRow == row)
        }
        .buttonStyle(.plain)
        .focused($focusedRow, equals: row)
        .opacity(0.55)
    }

    /// v136 焦点样式：无灰底；焦点行 = 白色描边 + 放大动画
    private func rowContent(title: String, subtitle: String, badge: String?, focused: Bool) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.65))
            }
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(focused ? .black : .white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(focused ? Color.white.opacity(0.92) : Color.white.opacity(0.18)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white, lineWidth: focused ? 4 : 0)
        )
        .scaleEffect(focused ? 1.05 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: focused)
    }
}
