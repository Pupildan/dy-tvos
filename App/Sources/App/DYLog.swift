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

    private override init() {
        super.init()
    }

    /// 记录一条日志（同时留屏上可读）。
    func log(_ msg: String) {
        let line = "[\(Self.ts())] \(msg)"
        queue.async {
            self.lines.append(line)
            if self.lines.count > self.maxLines { self.lines.removeFirst(self.lines.count - self.maxLines) }
        }
        NSLog("%@", line) // 兜底进系统日志
    }

    private static func ts() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }

    private func snapshot() -> String {
        queue.sync { lines.joined(separator: "\n") }
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
            body = snapshot() + "\n"
        case "/ping":
            status = "200 OK"
            body = "ok\n"
        case "/clear":
            queue.async { self.lines.removeAll() }
            status = "200 OK"
            body = "cleared\n"
        default:
            status = "404 Not Found"
            body = "endpoints: /log /ping /clear\n"
        }
        let payload = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        conn.send(content: payload.data(using: .utf8), completion: .contentProcessed { _ in
            conn.cancel()
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
