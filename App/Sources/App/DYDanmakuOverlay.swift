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
    required init(frame: CGRect) {
        super.init(frame: frame)
        // 关键：DanmakuAsyncLayer 在 layer isOpaque==true 时会主动填白（白底来源）——显式关掉
        // （官方 example 同款：backgroundColor = .clear；再加 isOpaque=false 双保险）
        backgroundColor = .clear
        isOpaque = false
        layer.isOpaque = false
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
    /// 已发射过的弹幕 id 集合（v139：替代 shotIndex——分段乱序追加容忍 + seek 回退可重弹）
    private var shotIds = Set<String>()
    private var loadedAwemeId = ""
    private var fetchRequested = false
    private var timer: Timer?
    /// 弹幕总开关（v132 默认开；v135 起由设置面板「弹幕设置」统一控制）
    static var globalEnabled = UserDefaults.standard.object(forKey: "dy_danmaku_on") == nil
        ? true
        : UserDefaults.standard.bool(forKey: "dy_danmaku_on")
    /// 单 overlay 开关（预留）
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
    /// v138 分段取回；v139 onSegment 可能乱序追加（重试段）——追加后按 offset 重排，发射器用 id 去重扫描。
    func load(awemeId: String, durationMs: Int) {
        guard loadedAwemeId != awemeId else { return }
        loadedAwemeId = awemeId
        items = []
        shotIds = []
        fetchRequested = false
        danmakuView.stop()
        danmakuView.clean()
        guard !awemeId.isEmpty else { return }
        fetchRequested = true
        DYLog.shared.log("DMLOAD id=\(awemeId) dur=\(durationMs)")
        DYDanmakuClient.shared.items(for: awemeId, durationMs: durationMs, onSegment: { [weak self] seg in
            guard let self, self.loadedAwemeId == awemeId else { return }   // 已换片则丢弃
            self.appendItems(seg)
        }, completion: { [weak self] in
            guard let self, self.loadedAwemeId == awemeId else { return }
            DYLog.shared.log("DMLOAD done id=\(awemeId) total=\(self.items.count)")
        })
    }

    /// 播放态同步（居中且在播 → play 并对齐时钟；否则 pause）。
    func syncPlaying(_ playing: Bool) {
        guard enabled else { return }
        if playing {
            if danmakuView.status == .stop || danmakuView.status == .pause {
                danmakuView.play()
            }
            ensureTimer()
        } else {
            danmakuView.pause()
        }
    }

    /// seek 后：清屏（回退重播时段幕会随时间重新飘出；已发射集合保留防同屏重复）。
    /// v139：shotIds 保留不清——seek 回退时旧弹幕不重放（与抖音观感一致）；前拖跳过的照常跳过。
    func seekSync() {
        guard enabled else { return }
        danmakuView.clean()
    }

    func stopAndClean() {
        danmakuView.stop()
        danmakuView.clean()
        shotIds = []
        items = []
        loadedAwemeId = ""
        timer?.invalidate()
        timer = nil
    }

    private func ensureTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 追加弹幕（可能乱序——重试段晚到）：按 offset 重排保持 tick 的顺序扫描假设。
    private func appendItems(_ seg: [DYDanmakuItem]) {
        guard !seg.isEmpty else { return }
        items.append(contentsOf: seg)
        items.sort { $0.offsetTime < $1.offsetTime }
    }

    /// 发射器：按播放时钟扫描到点的弹幕 shoot 出去（id 去重，容忍乱序追加）。
    /// 迟到 40s 以上的放弃（防堆积爆屏；分段重试晚到的部分照常参与）。
    private func tick() {
        guard Self.globalEnabled, enabled, !items.isEmpty, danmakuView.status == .play, player?.timeControlStatus == .playing else { return }
        let t = (player?.currentTime().seconds ?? 0) * 1000
        var shot = 0
        for item in items {
            if item.offsetTime > t { break }   // 有序：后面的都还没到点
            if shotIds.contains(item.danmakuId) { continue }
            guard t - item.offsetTime < 40_000 else { continue }   // 迟到过久的放弃
            shotIds.insert(item.danmakuId)
            let model = DanmakuTextCellModel(danmakuId: item.danmakuId.isEmpty ? "\(loadedAwemeId)-\(shotIds.count)" : item.danmakuId,
                                             text: item.text,
                                             screenW: max(200, bounds.width))
            danmakuView.shoot(danmaku: model)
            shot += 1
        }
        if shot > 0 { DYLog.shared.count("dm_shoot", by: shot) }
    }
}
