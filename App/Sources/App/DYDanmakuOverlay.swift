import UIKit
import AVFoundation

/// 弹幕文字模型（DanmakuKit DanmakuCellModel 协议实现）。
/// displayTime = 滚屏总时长 = (屏宽+文字宽)/速度；identifier 用 danmaku_id（去重/等值判断）。
final class DanmakuTextCellModel: DanmakuCellModel {
    let text: String
    let sizeValue: CGSize
    let displayTimeValue: Double
    let identifierValue: String

    var cellClass: DanmakuCell.Type { DanmakuTextCell.self }
    var size: CGSize { sizeValue }
    var track: UInt?
    var displayTime: Double { displayTimeValue }
    var type: DanmakuCellType { .floating }
    var identifier: String { identifierValue }

    func isEqual(to cellModel: DanmakuCellModel) -> Bool {
        cellModel.identifier == identifier
    }

    init(danmakuId: String, text: String, screenW: CGFloat) {
        self.text = text
        self.identifierValue = danmakuId
        // tvOS 1080p 场景字号
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 38),
        ]
        let measured = (text as NSString).size(withAttributes: attrs)
        let w = min(measured.width + 8, screenW - 40)
        sizeValue = CGSize(width: w, height: measured.height + 8)
        // 滚动速度 ~300px/s（1080p 观感与主流播放器一致）
        displayTimeValue = max(4.0, (screenW + w) / 300.0)
    }
}

/// 弹幕文字 Cell：DanmakuKit 异步图层上画纯色文字（v134 用户要求：无背景、无描边，保留弹幕本身颜色）。
final class DanmakuTextCell: DanmakuCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        // 关键：DanmakuAsyncLayer 在 isOpaque==true 时会主动填白（白底来源）——必须显式关掉
        isOpaque = false
        layer.isOpaque = false
        backgroundColor = nil
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func displaying(_ context: CGContext, _ size: CGSize, _ isCancelled: Bool) {
        guard let model = model as? DanmakuTextCellModel else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 38),
            .foregroundColor: UIColor.white,
        ]
        model.text.draw(in: CGRect(x: 0, y: 2, width: size.width, height: size.height), withAttributes: attrs)
    }
}

/// 弹幕覆盖层：包 DanmakuView（Core Animation 驱动，滚屏平滑）+ 按播放时钟发射器。
/// 生命周期由控制器驱动：load(awemeId:) 换片 → syncPlaying 播放态 → seekSync 拖动。
/// tvOS 焦点隔离：isUserInteractionEnabled=false，不参与焦点/按键（渲染纯展示层）。
final class DanmakuOverlay: UIView {
    private let danmakuView: DanmakuView
    private weak var player: AVPlayer?
    private var items: [DYDanmakuItem] = []
    private var shotIndex = 0
    private var loadedAwemeId = ""
    private var fetchRequested = false
    private var timer: Timer?
    /// 弹幕总开关（v132 默认开；UI 开关待美化阶段统一做）
    var enabled = true

    var currentAwemeId: String { loadedAwemeId }

    override init(frame: CGRect) {
        danmakuView = DanmakuView(frame: .zero)
        super.init(frame: frame)
        isUserInteractionEnabled = false
        danmakuView.isUserInteractionEnabled = false
        // tvOS 1080p 参数：轨道高 46px，弹幕铺上半屏（55%），不重叠（密集时让位）
        danmakuView.trackHeight = 46
        danmakuView.displayArea = 0.55
        danmakuView.isOverlap = false
        danmakuView.enableCellReusable = true
        addSubview(danmakuView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        danmakuView.frame = bounds
    }

    func bind(player: AVPlayer?) {
        self.player = player
    }

    /// 换片：清空 + 重取该 aweme 的弹幕（awemeId 未变则跳过）。
    func load(awemeId: String, durationMs: Int) {
        guard loadedAwemeId != awemeId else { return }
        loadedAwemeId = awemeId
        items = []
        shotIndex = 0
        fetchRequested = false
        danmakuView.stop()
        danmakuView.clean()
        guard !awemeId.isEmpty else { return }
        fetchRequested = true
        DYLog.shared.log("DMLOAD id=\(awemeId) dur=\(durationMs)")
        DYDanmakuClient.shared.items(for: awemeId, durationMs: durationMs) { [weak self] items in
            guard let self, self.loadedAwemeId == awemeId else { return }   // 已换片则丢弃
            self.items = items
            DYLog.shared.count("dm_items", by: items.count)
        }
    }

    /// 播放态同步（居中且在播 → play 并对齐时钟；否则 pause）。
    func syncPlaying(_ playing: Bool) {
        guard enabled else { return }
        if playing {
            let t = player?.currentTime().seconds ?? 0
            if danmakuView.status == .stop || danmakuView.status == .pause {
                let wasStop = danmakuView.status == .stop
                danmakuView.play()
                if wasStop {
                    recalcCursor(atMs: t * 1000)   // 首次播放：游标对齐到当前时间
                }
            }
            ensureTimer()
        } else {
            danmakuView.pause()
        }
    }

    /// seek 后：清屏 + 游标重算（回拖重放，前拖跳过的直接略过）。
    func seekSync() {
        guard enabled, !items.isEmpty else { return }
        danmakuView.clean()
        let t = (player?.currentTime().seconds ?? 0) * 1000
        recalcCursor(atMs: t - 1500)   // 刚过 1.5s 内的补射，更早的跳过
    }

    func stopAndClean() {
        danmakuView.stop()
        danmakuView.clean()
        shotIndex = 0
        items = []
        loadedAwemeId = ""
        timer?.invalidate()
        timer = nil
    }

    private func recalcCursor(atMs t: Double) {
        guard !items.isEmpty else { shotIndex = 0; return }
        shotIndex = items.firstIndex { $0.offsetTime >= t } ?? items.count
    }

    private func ensureTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 发射器：按播放时钟把到点的弹幕 shoot 出去（shoot 要求 danmakuView 处于 .play）。
    private func tick() {
        guard enabled, !items.isEmpty, danmakuView.status == .play, player?.timeControlStatus == .playing else { return }
        guard shotIndex < items.count else { return }
        let t = (player?.currentTime().seconds ?? 0) * 1000
        while shotIndex < items.count, items[shotIndex].offsetTime <= t {
            let item = items[shotIndex]
            if t - item.offsetTime < 2500 {   // 迟到 2.5s 以上的不再补射（防止堆积）
                let model = DanmakuTextCellModel(danmakuId: item.danmakuId.isEmpty ? "\(loadedAwemeId)-\(shotIndex)" : item.danmakuId,
                                                 text: item.text,
                                                 screenW: max(200, bounds.width))   // v134: 用视频区域实际宽度算滚屏时长
                danmakuView.shoot(danmaku: model)
                DYLog.shared.count("dm_shoot")
            }
            shotIndex += 1
        }
    }
}
