import UIKit

// MARK: - 直播弹幕底部聊天列表（抖音样式：新消息从底部往上推，带 @昵称，纯展示层）
// v217 彻底重写为 frame 布局——v216 诊断实锤 overlay 高度被 autolayout 塌缩到 2-10px（height<=0.45 只上限
// + stack top>=top 允许塌缩），聊天行被压成一条线。frame 布局尺寸/位置完全确定，消灭 autolayout 塌缩这一整类问题。
// tvOS 焦点隔离：isUserInteractionEnabled=false，不参与焦点/触摸，照 VOD DanmakuOverlay。
final class DYLiveChatOverlay: UIView {
    /// 最多同时显示几条（抖音直播约 5-7 条）
    private let maxRows = 6
    private let rowHeight: CGFloat = 52
    private let rowSpacing: CGFloat = 6
    private var chatRows: [ChatRow] = []

    /// 单条聊天行（纯展示，frame 布局：外部直接设 frame，内部 label 铺满）
    final class ChatRow: UIView {
        let label = UILabel()
        init() {
            super.init(frame: .zero)
            label.numberOfLines = 1
            label.font = .systemFont(ofSize: 26, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        required init?(coder: NSCoder) { fatalError() }

        func configure(nickname: String, content: String) {
            // @昵称 高亮（抖音直播浅色）+ 内容白字，均带阴影（照 DanmakuKit 文字样式）
            let nick = nickname.isEmpty ? "" : "@\(nickname)"
            let attr = NSMutableAttributedString()
            if !nick.isEmpty {
                attr.append(NSAttributedString(string: nick, attributes: [
                    .font: UIFont.systemFont(ofSize: 26, weight: .bold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                ]))
                attr.append(NSAttributedString(string: " ", attributes: [.font: UIFont.systemFont(ofSize: 26)]))
            }
            attr.append(NSAttributedString(string: content, attributes: [
                .font: UIFont.systemFont(ofSize: 26, weight: .medium),
                .foregroundColor: UIColor.white,
            ]))
            // 阴影（照 DanmakuKit 文字阴影，保证在亮画面上可读）
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 1
            label.layer.shadowRadius = 2
            label.layer.shadowOffset = CGSize(width: 1, height: 1)
            label.attributedText = attr
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false   // tvOS 焦点隔离（照 VOD DanmakuOverlay）
        clipsToBounds = false
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 追加一条聊天（主队列）。frame 布局：加入数组 → layoutSubviews 按底部向上定位。超 maxRows 移除最旧。
    func append(nickname: String, content: String) {
        guard !content.isEmpty else { return }
        let row = ChatRow()
        row.configure(nickname: nickname, content: content)
        addSubview(row)
        chatRows.append(row)
        // 超出上限移除最旧
        while chatRows.count > maxRows {
            let oldest = chatRows.removeFirst()
            oldest.removeFromSuperview()
        }
        setNeedsLayout()
        layoutIfNeeded()
        // v217 诊断：确认每行 frame 落在 overlay 内、overlay 自身尺寸/位置正常
        let frames = chatRows.map { "(\(Int($0.frame.origin.x)),\(Int($0.frame.origin.y)),\(Int($0.frame.width)),\(Int($0.frame.height)))" }.joined(separator: " ")
        DYLog.shared.log("LIVE CHAT append n=\(chatRows.count) overlay=(\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.width)),\(Int(frame.height))) rows=[\(frames)] hidden=\(isHidden) superview=\(superview.map { String(describing: type(of: $0)) } ?? "nil")")
    }

    /// 切房清空
    func clear() {
        chatRows.forEach { $0.removeFromSuperview() }
        chatRows.removeAll()
        setNeedsLayout()
    }

    /// frame 布局：行从底部往上堆叠（新消息在最底），行间距 rowSpacing
    override func layoutSubviews() {
        super.layoutSubviews()
        let total = chatRows.count
        guard total > 0 else { return }
        for (i, row) in chatRows.enumerated() {
            // i=0 最旧（最上），i=total-1 最新（最下）
            let rowsFromBottom = total - i
            let y = bounds.height - CGFloat(rowsFromBottom) * rowHeight - CGFloat(rowsFromBottom - 1) * rowSpacing
            row.frame = CGRect(x: 0, y: y, width: bounds.width, height: rowHeight)
        }
    }
}
