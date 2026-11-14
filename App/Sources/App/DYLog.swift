import Foundation
import Network

/// 极简局域网日志服务器：ATV 监听 TCP，Bonjour 广播，开发机 curl 拉日志。
/// 用途：P2 探测/抓链/播放诊断不再依赖屏上小字，开发机直接 `curl http://<ATV-IP>:8765/log`。
/// 待真机验证：tvOS App Sandbox 是否允许免费 sideload 监听入站 TCP（无法静态保证）。
final class DYLog: NSObject {
    static let shared = DYLog()
    static let port: UInt16 = 8765

    private let queue = DispatchQueue(label: "dy.log.server")
    private var listener: NWListener?
    private var service: NetService?
    private var lines: [String] = []
    private let maxLines = 500
    /// 事件计数器(key→次数)——/stat 一屏看全,快速定位问题在哪个环节(ready/novideo/stall/repair/skip/...)
    private var counters: [String: Int] = [:]
    /// 诊断事件环(最近 40 条)——/stat 直接给关键事件时间线,免 grep 500 行
    private var events: [String] = []
    private let maxEvents = 40

    // 出站推送：ATV 主动连开发机收集器（出站稳，绕开入站监听/ATS 限制）
    static let collectorHost = "192.168.10.122"
    static let collectorPort: UInt16 = 9988
    private var pushConn: NWConnection?
    private var pushReady = false
    private var pushAttempts = 0

    private override init() {
        super.init()
    }

    /// 记录一条日志（同时留屏上可读 + 推送到开发机收集器）。
    func log(_ msg: String) {
        let line = "[\(Self.ts())] \(msg)"
        queue.async {
            self.lines.append(line)
            if self.lines.count > self.maxLines { self.lines.removeFirst(self.lines.count - self.maxLines) }
            self.push(line)
        }
        NSLog("%@", line) // 兜底进系统日志
    }

    /// 计数器 +1（任意 key，/stat 汇总输出）。用于各环节量级监控：成功率、跳过次数等。
    func count(_ key: String, by increment: Int = 1) {
        queue.async { self.counters[key, default: 0] += increment }
    }

    /// 诊断事件：进常规日志（推送开发机）+ 进 /stat 事件环。
    /// 用于坏视频/看门狗动作/换源等关键节点——真机出问题时 `curl http://<ATV-IP>:8765/stat` 一次看全。
    func event(_ msg: String) {
        let stamp = "[\(Self.ts())] \(msg)"
        queue.async {
            self.events.append(stamp)
            if self.events.count > self.maxEvents { self.events.removeFirst(self.events.count - self.maxEvents) }
        }
        log(msg)
    }

    /// 推送就绪时回灌缓冲历史（连接建立前的日志不再丢失——SIGNER 早期行可见）。
    private func flushBufferedLines() {
        guard let conn = pushConn, !lines.isEmpty else { return }
        let payload = lines.joined(separator: "\n") + "\n"
        conn.send(content: Data(payload.utf8), completion: .contentProcessed { _ in })
    }

    /// 出站推送一行到开发机收集器（raw TCP）。连接懒建立；若始终未 ready，定期拆掉重建（自愈）。
    private func push(_ line: String) {
        if pushConn == nil {
            pushAttempts = 0
            let c = NWConnection(host: NWEndpoint.Host(Self.collectorHost),
                                 port: NWEndpoint.Port(rawValue: Self.collectorPort)!,
                                 using: .tcp)
            c.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.queue.async {
                        self?.pushReady = true
                        self?.pushAttempts = 0
                        self?.flushBufferedLines()
                    }
                case .failed, .cancelled:
                    self?.queue.async { self?.pushReady = false; self?.pushConn = nil }
                default:
                    break
                }
            }
            c.start(queue: queue)
            pushConn = c
        }
        guard let conn = pushConn, pushReady else {
            // 未 ready：累计尝试次数，超过阈值拆掉重连（解 .waiting 卡死）
            pushAttempts += 1
            if pushAttempts > 8, let stale = pushConn {
                stale.cancel()
                pushConn = nil
            }
            return
        }
        let payload = Data((line + "\n").utf8)
        conn.send(content: payload, completion: .contentProcessed { _ in })
    }

    private static func ts() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    private func snapshot() -> String {
        queue.sync { lines.joined(separator: "\n") }
    }

    /// 有界快照：只取末 N 行、每行截断，保证 /log 响应小而稳定（避免大响应重置连接）。
    private func boundedSnapshot(maxLines: Int = 50, maxLineLen: Int = 160) -> String {
        queue.sync {
            let tail = lines.suffix(maxLines)
            let trimmed = tail.map { $0.count > maxLineLen ? String($0.prefix(maxLineLen)) + "…" : $0 }
            let omitted = max(0, lines.count - maxLines)
            let head = omitted > 0 ? "…(\(omitted) earlier lines omitted)\n" : ""
            return head + trimmed.joined(separator: "\n")
        }
    }

    /// /stat 诊断总览：版本 + 计数器全量 + 最近诊断事件环 + 最近直链。
    /// 真机排障一次 curl 看全：哪个环节失败（novideo/stall/repair/skip 计数）+ 时间线。
    private func stats() -> String {
        queue.sync {
            var out: [String] = []
            out.append("version=\(DYBuild.version)")
            out.append("total_lines=\(lines.count)")
            let pairs = counters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
            out.append("counters: " + (pairs.isEmpty ? "(none)" : pairs.joined(separator: " ")))
            out.append("--- recent diag events (\(events.count)) ---")
            out.append(contentsOf: events.suffix(15))
            let videoLines = lines.filter { $0.contains(".mp4") || $0.contains(".m3u8") || $0.contains("douyinvod") }
            let lastVideo = videoLines.last ?? "(none)"
            let trimmedLast = lastVideo.count > 200 ? String(lastVideo.prefix(200)) + "…" : lastVideo
            out.append("last_video=\(trimmedLast)")
            return out.joined(separator: "\n")
        }
    }

    /// 启动监听 + Bonjour 广播。幂等。
    func start() {
        queue.async { self._start() }
    }

    private func _start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // 不绑定具体接口 → 默认 Wi-Fi/Ethernet，同网段可达
        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!) else {
            log("LOGSRV FAIL: cannot create NWListener")
            return
        }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.log("LOGSRV ready on port \(Self.port)")
                self?.advertise()
            case .failed(let err):
                self?.log("LOGSRV FAILED: \(err) (App Sandbox 可能拦截入站 TCP)")
            case .waiting(let err):
                self?.log("LOGSRV waiting: \(err)")
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    private func advertise() {
        guard service == nil else { return }
        let name = "DYTV-\(Int.random(in: 100...999))"
        let svc = NetService(domain: "local.", type: "_dylog._tcp.", name: name, port: Int32(Self.port))
        service = svc
        svc.delegate = self
        svc.schedule(in: .main, forMode: .default)
        svc.publish()
        log("LOGSRV advertising as \(name)")
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn)
    }

    private func receive(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, err in
            guard let self else { return }
            if let data, !data.isEmpty, let req = String(data: data, encoding: .utf8) {
                self.respond(conn, request: req)
                return // 单次请求即断（curl 友好）
            }
            if done || err != nil {
                conn.cancel()
                return
            }
            self.receive(conn)
        }
    }

    private func respond(_ conn: NWConnection, request req: String) {
        let firstLine = req.split(separator: "\r\n").first.map(String.init) ?? ""
        let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        let (status, body): (String, String)
        switch path {
        case "/log":
            status = "200 OK"
            body = boundedSnapshot() + "\n"
        case "/stat":
            status = "200 OK"
            body = stats() + "\n"
        case "/ping":
            status = "200 OK"
            body = "ok\n"
        case "/clear":
            queue.async { self.lines.removeAll() }
            status = "200 OK"
            body = "cleared\n"
        default:
            status = "404 Not Found"
            body = "endpoints: /log /stat /ping /clear\n"
        }
        let payload = Data(("HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n" + body).utf8)
        // 分块发送，仅最后一处理完才关连接：
        // .contentProcessed 只代表"已交给协议栈"，大响应立即 cancel 会截断（curl 56）。
        sendChunked(conn, data: payload)
    }

    private func sendChunked(_ conn: NWConnection, data: Data, offset: Int = 0) {
        let chunk = 16384
        if offset >= data.count {
            conn.cancel()
            return
        }
        let end = min(offset + chunk, data.count)
        let slice = data.subdata(in: offset..<end)
        let isLast = (end >= data.count)
        conn.send(content: slice, completion: .contentProcessed { [weak self] _ in
            if isLast {
                conn.cancel()
            } else {
                self?.sendChunked(conn, data: data, offset: end)
            }
        })
    }
}

extension DYLog: NetServiceDelegate {
    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        log("LOGSRV Bonjour didNotPublish: \(errorDict)")
    }
    func netServiceDidPublish(_ sender: NetService) {
        log("LOGSRV Bonjour published: \(sender.name)")
    }
}
