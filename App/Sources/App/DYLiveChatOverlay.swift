import UIKit

// MARK: - 直播弹幕底部聊天列表（抖音样式：新消息从底部往上推，带 @昵称，纯展示层）
// 渲染思路沿用本项目 DanmakuKit 的文字 cell（白字+阴影），但布局改为底部纵向堆叠（用户选抖音样式，非横向飘过）。
// tvOS 焦点隔离：isUserInteractionEnabled=false，不参与焦点/触摸，照 VOD DanmakuOverlay。
final class DYLiveChatOverlay: UIView {
    /// 最多同时显示几条（抖音直播约 5-7 条）
    private let maxRows = 6
    private let rowSpacing: CGFloat = 6
    private let fontSize: CGFloat = 26
    private let rows: [ChatRow] = []

    private let stack = UIStackView()
    private let containerWidth: CGFloat

    /// 单条聊天行（纯展示）
    final class ChatRow: UIView {
        let label = UILabel()
        init(width: CGFloat) {
            super.init(frame: .zero)
            label.numberOfLines = 0
            label.font = .systemFont(ofSize: 26, weight: .medium)
            translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
                label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
                label.leadingAnchor.constraint(equalTo: leadingAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            ])
        }
        required init?(coder: NSCoder) { fatalError() }

        func configure(nickname: String, content: String) {
            // @昵称 高亮（抖音直播浅色）+ 内容白字，均带阴影（照 DanmakuKit 文字样式）
            let nick = nickname.isEmpty ? "" : "@\(nickname)"
            let attr = NSMutableAttributedString()
            if !nick.isEmpty {
                attr.append(NSAttributedString(string: nick, attributes: [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                ]))
                attr.append(NSAttributedString(string: " ", attributes: [.font: UIFont.systemFont(ofSize: fontSize)]))
            }
            attr.append(NSAttributedString(string: content, attributes: [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: UIColor.white,
            ]))
            // 阴影（照 DanmakuKit 文字阴影，保证在亮画面上可读）
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 1
            label.layer.shadowRadius = 2
            label.layer.shadowOffset = CGSize(width: 1, height: 1)
            label.attributedText = attr
        }

        private var fontSize: CGFloat { 26 }
    }

    init(containerWidth: CGFloat) {
        self.containerWidth = max(300, containerWidth)
        super.init(frame: .zero)
        isUserInteractionEnabled = false   // tvOS 焦点隔离（照 VOD DanmakuOverlay）
        translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = rowSpacing
        stack.alignment = .leading
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 追加一条聊天（主队列）。新消息推到底部，超 maxRows 移除最旧。
    func append(nickname: String, content: String) {
        guard !content.isEmpty else { return }
        let row = ChatRow(width: containerWidth)
        row.configure(nickname: nickname, content: content)
        stack.addArrangedSubview(row)
        row.layoutIfNeeded()
        // 淡入 + 轻微上移（抖音直播新消息浮现）
        row.alpha = 0
        row.transform = CGAffineTransform(translationX: 0, y: 12)
        UIView.animate(withDuration: 0.25, animations: {
            row.alpha = 1
            row.transform = .identity
        })
        // 超出上限移除最旧（带淡出）
        while stack.arrangedSubviews.count > maxRows, let oldest = stack.arrangedSubviews.first {
            stack.removeArrangedSubview(oldest)
            UIView.animate(withDuration: 0.2, animations: { oldest.alpha = 0 }) { _ in oldest.removeFromSuperview() }
        }
    }

    /// 切房清空
    func clear() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: containerWidth, height: stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height)
    }
}
