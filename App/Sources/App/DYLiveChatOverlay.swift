import UIKit

// MARK: - 直播弹幕底部聊天列表（抖音样式：新消息从底部往上推，带 @昵称，纯展示层）
// v217 彻底重写为 frame 布局——v216 诊断实锤 overlay 高度被 autolayout 塌缩到 2-10px（height<=0.45 只上限
// + stack top>=top 允许塌缩），聊天行被压成一条线。frame 布局尺寸/位置完全确定，消灭 autolayout 塌缩这一整类问题。
// tvOS 焦点隔离：isUserInteractionEnabled=false，不参与焦点/触摸，照 VOD DanmakuOverlay。
final class DYLiveChatOverlay: UIView {
    /// 最多同时显示几条（抖音直播约 5-7 条）
    private let maxRows = 6
    /// 单行最小高度（v221：超长弹幕换行时行高按内容撑高，此为下限）
    static let rowMinHeight: CGFloat = 44
    private let rowSpacing: CGFloat = 4
    private var chatRows: [ChatRow] = []

    /// 单条聊天行（纯展示，frame 布局：外部直接设 frame，内部 label 铺满）
    final class ChatRow: UIView {
        let label = UILabel()
        init() {
            super.init(frame: .zero)
            // v221：超长弹幕要自动换行（v217 的 numberOfLines=1 把长弹幕截断了）
            label.numberOfLines = 0
            label.font = .systemFont(ofSize: 22, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
                // label 铺满行高（行高由 height(forWidth:) 按内容动态算，UILabel 默认垂直居中）
                label.topAnchor.constraint(equalTo: topAnchor),
                label.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        required init?(coder: NSCoder) { fatalError() }

        /// v221：按可用宽度测本行需要的高度（单行=最小行高，超长换行则撑高）。
        func height(forWidth w: CGFloat) -> CGFloat {
            let attr = label.attributedText ?? NSAttributedString()
            let b = attr.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude),
                                      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            return max(DYLiveChatOverlay.rowMinHeight, ceil(b.height) + 10)   // +10 上下留白
        }

        func configure(nickname: String, content: String, emojiImages: [String: UIImage]) {
            // v219：去掉 @ 符号（用户要求）。昵称高亮 + 内容白字 + 内联表情图片，均带阴影。
            let nick = nickname
            let attr = NSMutableAttributedString()
            if !nick.isEmpty {
                attr.append(NSAttributedString(string: nick, attributes: [
                    .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                ]))
                attr.append(NSAttributedString(string: "：", attributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.white.withAlphaComponent(0.85)]))
            }
            // v219：内容里的 [表情] shortcode 渲染成内联图片（表情包），文字正常排
            attr.append(emojiAttributedContent(content, emojiImages: emojiImages))
            // 阴影（照 DanmakuKit 文字阴影，保证在亮画面上可读）
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 1
            label.layer.shadowRadius = 2
            label.layer.shadowOffset = CGSize(width: 1, height: 1)
            label.attributedText = attr
        }

        /// v219：把 content 里的 [表情] shortcode 替换成内联表情图片（NSTextAttachment），文字原样保留。
        private func emojiAttributedContent(_ content: String, emojiImages: [String: UIImage]) -> NSAttributedString {
            let out = NSMutableAttributedString()
            // 按 [xxx] 切分：正则抓所有 [..] 段，段间是普通文字
            let regex = try? NSRegularExpression(pattern: "\\[([^\\[\\]]+)\\]")
            let ns = content as NSString
            var cursor = 0
            let matches = regex?.matches(in: content, range: NSRange(location: 0, length: ns.length)) ?? []
            for m in matches {
                if m.range.location > cursor {
                    out.append(NSAttributedString(string: ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)), attributes: textAttrs))
                }
                let shortcode = ns.substring(with: m.range)             // 含方括号，如 [捂脸]
                if let img = emojiImages[shortcode] {
                    out.append(imageAttachment(img))
                } else {
                    out.append(NSAttributedString(string: shortcode, attributes: textAttrs))   // 无映射→原样文本
                }
                cursor = m.range.location + m.range.length
            }
            if cursor < ns.length {
                out.append(NSAttributedString(string: ns.substring(from: cursor), attributes: textAttrs))
            }
            if out.length == 0 { out.append(NSAttributedString(string: content, attributes: textAttrs)) }
            return out
        }

        private var textAttrs: [NSAttributedString.Key: Any] {
            [.font: UIFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: UIColor.white]
        }

        /// 表情图片转 NSTextAttachment（按文字行高缩放）
        private func imageAttachment(_ img: UIImage) -> NSAttributedString {
            let att = NSTextAttachment()
            let side: CGFloat = 28
            att.image = img
            att.bounds = CGRect(x: 0, y: -4, width: side, height: side)
            return NSAttributedString(attachment: att)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false   // tvOS 焦点隔离（照 VOD DanmakuOverlay）
        clipsToBounds = false
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 追加一条聊天（主队列）。emojiImages=shortcode→图片（表情包内联渲染）。frame 布局：加入数组 → layoutSubviews 按底部向上定位。
    func append(nickname: String, content: String, emojiImages: [String: UIImage]) {
        guard !content.isEmpty else { return }
        let row = ChatRow()
        row.configure(nickname: nickname, content: content, emojiImages: emojiImages)
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

    /// frame 布局：行从底部往上堆叠（新消息在最底），行间距 rowSpacing。
    /// v221：每行高度按内容动态算（超长弹幕换行撑高），从最新(最底)往最旧(最上)排，超出顶部自然裁掉。
    override func layoutSubviews() {
        super.layoutSubviews()
        let total = chatRows.count
        guard total > 0 else { return }
        let availW = bounds.width
        guard availW > 0 else { return }
        var y = bounds.height
        // 从最新(i=total-1，最底)往最旧(i=0，最上)排：每行先上移自身高度再定位，再扣间距
        for i in stride(from: total - 1, through: 0, by: -1) {
            let row = chatRows[i]
            let h = row.height(forWidth: availW)
            y -= h
            row.frame = CGRect(x: 0, y: y, width: availW, height: h)
            y -= rowSpacing
        }
    }
}
