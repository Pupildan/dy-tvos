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

    /// 呼出/退出面板（Menu 按键状态机由控制器调用；显示中再按 Menu=退出应用走系统默认）
    func openPanel() {
        isOpen = true
        DYLog.shared.event("SETTINGS panel open (menu #1)")
    }

    /// 选视频源：切换 + 关面板。同源重复选 = 仅关面板。
    func selectSource(_ s: DYFeedSource) {
        source = s
        isOpen = false
        DanmakuOverlay.globalEnabled = danmakuOn
        if s != DYFeedClient.shared.source {
            DYFeedClient.shared.setSource(s)
        }
    }

    /// 弹幕设置：切开关（即时生效，不清播放）。
    func toggleDanmaku() {
        danmakuOn.toggle()
        DanmakuOverlay.globalEnabled = danmakuOn
        DYLog.shared.event("SETTINGS danmaku -> \(danmakuOn ? "on" : "off")")
    }

    /// 占位项（直播/登录）：只记日志，后续版本实施。
    func placeholderTapped(_ name: String) {
        DYLog.shared.event("SETTINGS placeholder \(name) (待实施)")
    }
}

/// 设置面板（屏幕左侧悬浮）：iOS 26 液态玻璃（tvOS 26 原生 glassEffect；低版本回退 ultraThinMaterial）。
/// 五项：移动端推荐 / 抖音精选 / 弹幕设置 / 直播(占位) / 登录(占位)。
struct SettingsPanelView: View {
    @ObservedObject var model = DYSettingsModel.shared

    var body: some View {
        HStack(alignment: .top) {
            panel
                .frame(width: 380)
                .padding(.leading, 28)
                .padding(.top, 40)
                .padding(.bottom, 40)
            Spacer(minLength: 0)
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

            sourceRow(title: "移动端推荐", subtitle: "手机端视频源", target: .mobile)
            sourceRow(title: "抖音精选", subtitle: "电脑端视频源", target: .web)
            danmakuRow
            placeholderRow(title: "直播", subtitle: "即将上线")
            placeholderRow(title: "登录", subtitle: "即将上线")

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

    private func sourceRow(title: String, subtitle: String, target: DYFeedSource) -> some View {
        Button {
            model.selectSource(target)
        } label: {
            rowContent(title: title, subtitle: subtitle,
                       badge: (model.source == target ? "当前" : nil),
                       highlight: model.source == target)
        }
        .buttonStyle(.plain)
    }

    private var danmakuRow: some View {
        Button {
            model.toggleDanmaku()
        } label: {
            rowContent(title: "弹幕设置", subtitle: model.danmakuOn ? "开启中（按 OK 关闭）" : "已关闭（按 OK 开启）",
                       badge: model.danmakuOn ? "开" : "关",
                       highlight: false)
        }
        .buttonStyle(.plain)
    }

    private func placeholderRow(title: String, subtitle: String) -> some View {
        Button {
            model.placeholderTapped(title)
        } label: {
            rowContent(title: title, subtitle: subtitle, badge: "待上线", highlight: false)
        }
        .buttonStyle(.plain)
        .opacity(0.55)
    }

    private func rowContent(title: String, subtitle: String, badge: String?, highlight: Bool) -> some View {
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
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.92)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(highlight ? 0.16 : 0.06))
        )
    }
}
