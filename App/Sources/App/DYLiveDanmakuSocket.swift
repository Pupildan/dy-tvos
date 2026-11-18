import Foundation
import CryptoKit

// MARK: - 直播弹幕 WebSocket 客户端（照反编译 myDV kq2.java / bp4.java / s30.java / jq2.java）
// 数据链：enter 取 roomId → msStub=MD5(k=v 串) → getMSSDKSignature(msStub,ua) → 拼 wss URL → 连
//   → join 帧(hb) → 10s 心跳 → 收二进制 PushFrame→gzip→Response→WebcastChatMessage → emit @昵称+内容 → needAck 回 ack
// 匿名可连（探针 live_danmaku_probe.js 已端到端验证：user_unique_id 用 ttwid）。
final class DYLiveDanmakuSocket: NSObject {
    struct ChatMessage { let nickname: String; let content: String }

    /// 收到一条聊天消息（主队列回调）
    var onChat: ((ChatMessage) -> Void)?
    /// 连接状态日志（主队列）
    var onLog: ((String) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var heartbeat: Timer?
    private var webRid = ""
    private var roomId = ""
    private var userId = ""          // 匿名用 ttwid
    private var cookie = ""          // ttwid=xxx
    private var reconnectAttempts = 0
    private let maxReconnect = 5
    private var manuallyClosed = false
    /// WS 专用 UA（照 kq2.java QQBrowser 串，与 REST 的 liveUA 一致）
    private let wsUA = DYLiveClient.liveUA

    // MARK: 连接
    func connect(room: DYLiveRoom, ttwid: String) {
        disconnect()
        manuallyClosed = false
        reconnectAttempts = 0
        self.webRid = room.webRid
        self.roomId = room.roomId.isEmpty ? room.webRid : room.roomId
        self.userId = ttwid
        self.cookie = ttwid.isEmpty ? "" : "ttwid=\(ttwid)"
        openSocket()
    }

    private func openSocket() {
        guard !roomId.isEmpty else { log("no roomId, skip"); return }
        // 1) msStub = MD5(逗号连接的 k=v 串)（照 bp4.java:143-160）
        let kv = [
            "live_id=1", "aid=6383", "version_code=180800", "webcast_sdk_version=1.3.0",
            "room_id=\(roomId)", "sub_room_id=", "sub_channel_id=", "did_rule=3",
            "user_unique_id=\(userId)", "device_platform=web", "device_type=", "ac=", "identity=audience",
        ].joined(separator: ",")
        let msStub = Data(kv.utf8).md5.hexString
        // 2) getMSSDKSignature(msStub, ua)（照 s30.java case 11）
        guard let signature = DYSigner.shared.msSign(stub: msStub, ua: wsUA), !signature.isEmpty else {
            log("msSign fail, skip connect")
            return
        }
        // 3) 拼 wss URL（照 kq2.java:126-130）
        let cursor = "h-1_t-\(Int(Date().timeIntervalSince1970 * 1000))_r-1_d-1_u-1"
        var comps = URLComponents(string: "wss://webcast3-ws-web-lq.douyin.com/webcast/im/push/v2/")
        comps?.queryItems = [
            URLQueryItem(name: "app_name", value: "douyin_web"),
            URLQueryItem(name: "version_code", value: "180800"),
            URLQueryItem(name: "webcast_sdk_version", value: "1.3.0"),
            URLQueryItem(name: "update_version_code", value: "1.3.0"),
            URLQueryItem(name: "compress", value: "gzip"),
            URLQueryItem(name: "cursor", value: cursor),
            URLQueryItem(name: "host", value: "https://live.douyin.com"),
            URLQueryItem(name: "aid", value: "6383"),
            URLQueryItem(name: "live_id", value: "1"),
            URLQueryItem(name: "did_rule", value: "3"),
            URLQueryItem(name: "debug", value: "false"),
            URLQueryItem(name: "maxCacheMessageNumber", value: "20"),
            URLQueryItem(name: "endpoint", value: "live_pc"),
            URLQueryItem(name: "support_wrds", value: "1"),
            URLQueryItem(name: "im_path", value: "/webcast/im/fetch/"),
            URLQueryItem(name: "user_unique_id", value: userId),
            URLQueryItem(name: "device_platform", value: "web"),
            URLQueryItem(name: "cookie_enabled", value: "true"),
            URLQueryItem(name: "screen_width", value: "1920"),
            URLQueryItem(name: "screen_height", value: "1080"),
            URLQueryItem(name: "browser_language", value: "zh-CN"),
            URLQueryItem(name: "browser_platform", value: "Win32"),
            URLQueryItem(name: "browser_name", value: "Mozilla"),
            URLQueryItem(name: "browser_version", value: "125.0.0.0"),
            URLQueryItem(name: "browser_online", value: "true"),
            URLQueryItem(name: "tz_name", value: "Asia/Shanghai"),
            URLQueryItem(name: "identity", value: "audience"),
            URLQueryItem(name: "room_id", value: roomId),
            URLQueryItem(name: "heartbeatDuration", value: "10"),
            URLQueryItem(name: "signature", value: signature),
        ]
        guard let url = comps?.url else { log("bad wss url"); return }

        // 4) 开 socket（自定义头：UA / Origin / Cookie，照 kq2.java:440-461）
        var req = URLRequest(url: url)
        req.setValue(wsUA, forHTTPHeaderField: "User-Agent")
        req.setValue("https://live.douyin.com", forHTTPHeaderField: "Origin")
        if !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let session = URLSession(configuration: .default)
        self.session = session
        let task = session.webSocketTask(with: req)
        self.task = task
        task.delegate = self
        task.resume()
        log("connecting webRid=\(webRid) roomId=\(roomId) sigLen=\(signature.count)")
    }

    // MARK: 发送
    private func sendFrame(payloadType: String, logId: UInt64, payload: Data) {
        let frame = KSPushFrame.encode(payloadType: payloadType, logId: logId, payload: payload)
        task?.send(.data(frame)) { [weak self] err in
            if let err { self?.log("send \(payloadType) err=\(err.localizedDescription)") }
        }
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            self?.sendFrame(payloadType: "hb", logId: 0, payload: Data())   // 照 jq2 join/heartbeat
        }
        RunLoop.main.add(t, forMode: .common)
        heartbeat = t
    }

    /// 回 ack（照 kq2.java:352-358：needAck 时回 PushFrame("ack", logId, internalExt)）
    private func sendAck(logId: UInt64, internalExt: String) {
        sendFrame(payloadType: "ack", logId: logId, payload: Data(internalExt.utf8))
    }

    // MARK: 断开
    func disconnect() {
        manuallyClosed = true
        heartbeat?.invalidate(); heartbeat = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func log(_ s: String) {
        let msg = "LIVE DM " + s
        DYLog.shared.log(msg)
        DispatchQueue.main.async { [weak self] in self?.onLog?(msg) }
    }

    /// 解流失败（供 KSMEPlayer 重试用）—— 这里只管弹幕，不处理
}

// MARK: - URLSessionWebSocketTaskDelegate
extension DYLiveDanmakuSocket: URLSessionWebSocketTaskDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        log("OPENED webRid=\(webRid)")
        reconnectAttempts = 0
        sendFrame(payloadType: "hb", logId: 0, payload: Data())   // join 帧
        startHeartbeat()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didReceive message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            handleBinary(data)
        case .string(let s):
            log("text msg (unexpected) len=\(s.count)")
        @unknown default:
            break
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        log("CLOSED code=\(closeCode.rawValue)")
        heartbeat?.invalidate(); heartbeat = nil
        scheduleReconnect()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { log("didComplete err=\(error.localizedDescription)") }
    }

    private func scheduleReconnect() {
        guard !manuallyClosed, reconnectAttempts < maxReconnect else { return }
        reconnectAttempts += 1
        let delay = 5.0
        log("reconnect \(reconnectAttempts)/\(maxReconnect) in \(Int(delay))s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.manuallyClosed else { return }
            self.openSocket()
        }
    }

    // MARK: 二进制消息解码（PushFrame → gzip → Response → WebcastChatMessage）
    private func handleBinary(_ data: Data) {
        let frame = KSPushFrame.decode(data)
        let ct = frame.headers["compress_type"] ?? frame.payloadType
        let isGz = ct.lowercased() == "gzip" || (frame.payload.count >= 2 && frame.payload[frame.payload.startIndex] == 0x1f && frame.payload[frame.payload.startIndex + 1] == 0x8b)
        let raw = isGz ? KSGzip.inflate(frame.payload) : frame.payload
        let resp = KSResponse.decode(raw)
        if resp.needAck { sendAck(logId: frame.logId, internalExt: resp.internalExt) }
        for m in resp.messages where m.method == "WebcastChatMessage" {
            let cm = KSChatMessage.decode(m.payload)
            guard !cm.content.isEmpty else { continue }
            let nick = cm.nickname.isEmpty ? "用户" : cm.nickname
            DispatchQueue.main.async { [weak self] in self?.onChat?(ChatMessage(nickname: nick, content: cm.content)) }
        }
    }
}

// MARK: - MD5 helper（msStub 用）
private extension Data {
    var md5: Data { Data(Insecure.MD5.hash(data: self)) }
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
