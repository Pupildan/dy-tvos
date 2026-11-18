import Foundation
import Compression

// MARK: - 直播弹幕 protobuf 最小编解码 + gzip 解压（照反编译 myDV x04.java / f70）
// 只实现 Webcast WS 需要的那几个 message：PushFrame / Response / WebcastChatMessage，以及 hb/ack 编码。
// protobuf wire format: 每字段 = tag(varint) = (fieldNumber<<3)|wireType；wireType 0=varint 1=fixed64 2=length-delimited 5=fixed32

/// protobuf wire 读取器（照 f70）
struct PBReader {
    let buf: [UInt8]
    var p: Int = 0
    init(_ data: Data) { buf = [UInt8](data) }
    var eof: Bool { p >= buf.count }

    /// 读一个 varint（最多 10 字节）
    mutating func varint() -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while p < buf.count {
            let b = buf[p]; p += 1
            result |= UInt64(b & 0x7f) << shift
            if b & 0x80 == 0 { break }
            shift += 7
        }
        return result
    }
    mutating func tag() -> UInt64 { varint() }
    /// 读 length-delimited 字节块
    mutating func bytes() -> Data {
        let len = Int(varint())
        guard len >= 0, p + len <= buf.count else { p = buf.count; return Data() }
        let d = Data(buf[p..<(p + len)]); p += len
        return d
    }
    mutating func str() -> String { String(data: bytes(), encoding: .utf8) ?? "" }
    /// 跳过未知字段
    mutating func skip(wireType: Int) {
        switch wireType {
        case 0: _ = varint()
        case 1: p += 8
        case 2: _ = bytes()
        case 5: p += 4
        default: p = buf.count
        }
    }
}

// MARK: - PushFrame（WS 每条二进制消息 = 一个 PushFrame）
struct KSPushFrame {
    var logId: UInt64 = 0
    var payloadType = ""
    var payload = Data()
    var headers: [String: String] = [:]
}

extension KSPushFrame {
    /// 解码 PushFrame（照 x04.s：tag2 logId / tag5 headers{1 key,2 value} / tag6 payloadType / tag7 payloadEncoding / tag8 payload）
    static func decode(_ data: Data) -> KSPushFrame {
        var f = KSPushFrame()
        var r = PBReader(data)
        while !r.eof {
            let t = r.tag(); let fn = Int(t >> 3), wt = Int(t & 7)
            if wt == 0 { let v = r.varint(); if fn == 2 { f.logId = v } }
            else if wt == 2 {
                let d = r.bytes()
                if fn == 5 {
                    var h = PBReader(d); var k = "", vv = ""
                    while !h.eof {
                        let ht = h.tag(); let hfn = Int(ht >> 3), hwt = Int(ht & 7)
                        if hwt == 0 { _ = h.varint() }
                        else if hwt == 2 { let s = h.str(); if hfn == 1 { k = s } else if hfn == 2 { vv = s } }
                        else { h.skip(wireType: hwt) }
                    }
                    if !k.isEmpty { f.headers[k] = vv }
                } else if fn == 6 { f.payloadType = String(data: d, encoding: .utf8) ?? "" }
                else if fn == 8 { f.payload = d }
            } else { r.skip(wireType: wt) }
        }
        return f
    }

    /// 编码 PushFrame（照 x04.n，仅 hb/ack 用：tag2 logId / tag7 payloadType / tag8 payload）
    static func encode(payloadType: String, logId: UInt64, payload: Data) -> Data {
        var out = Data()
        out.append(pbVarint((2 << 3) | 0)); out.append(pbVarint(logId))                 // tag2 logId varint
        let pt = payloadType.data(using: .utf8) ?? Data()
        out.append(pbVarint((7 << 3) | 2)); out.append(pbVarint(UInt64(pt.count))); out.append(pt)  // tag7 payloadType
        if !payload.isEmpty {
            out.append(pbVarint((8 << 3) | 2)); out.append(pbVarint(UInt64(payload.count))); out.append(payload)  // tag8 payload
        }
        return out
    }
}

/// 编码一个 varint
private func pbVarint(_ v: UInt64) -> Data {
    var out = Data(); var x = v
    repeat {
        var b = UInt8(x & 0x7f); x >>= 7
        if x > 0 { b |= 0x80 }
        out.append(b)
    } while x > 0
    return out
}

// MARK: - Response（PushFrame.payload 解压后 = 一个 Response）
struct KSResponse {
    struct Message { var method = ""; var payload = Data() }
    var messages: [Message] = []
    var internalExt = ""
    var needAck = false
}

extension KSResponse {
    /// 解码 Response（照 x04.t：tag1 repeated messages{1 method,2 payload} / tag5 internalExt / tag9 needAck）
    static func decode(_ data: Data) -> KSResponse {
        var resp = KSResponse()
        var r = PBReader(data)
        while !r.eof {
            let t = r.tag(); let fn = Int(t >> 3), wt = Int(t & 7)
            if wt == 0 { let v = r.varint(); if fn == 9 { resp.needAck = (v != 0) } }
            else if wt == 2 {
                let d = r.bytes()
                if fn == 1 {
                    var m = PBReader(d); var msg = Message()
                    while !m.eof {
                        let mt = m.tag(); let mfn = Int(mt >> 3), mwt = Int(mt & 7)
                        if mwt == 0 { _ = m.varint() }
                        else if mwt == 2 { let s = m.bytes(); if mfn == 1 { msg.method = String(data: s, encoding: .utf8) ?? "" } else if mfn == 2 { msg.payload = s } }
                        else { m.skip(wireType: mwt) }
                    }
                    resp.messages.append(msg)
                } else if fn == 5 { resp.internalExt = String(data: d, encoding: .utf8) ?? "" }
            } else { r.skip(wireType: wt) }
        }
        return resp
    }
}

// MARK: - WebcastChatMessage（聊天消息）
struct KSChatMessage {
    var nickname = ""
    var content = ""
}

extension KSChatMessage {
    /// 解码 WebcastChatMessage（照 x04.r：tag2 user{3 nickName} / tag3 content）
    static func decode(_ data: Data) -> KSChatMessage {
        var cm = KSChatMessage()
        var r = PBReader(data)
        while !r.eof {
            let t = r.tag(); let fn = Int(t >> 3), wt = Int(t & 7)
            if wt == 0 { _ = r.varint() }
            else if wt == 2 {
                let d = r.bytes()
                if fn == 2 {
                    var u = PBReader(d)
                    while !u.eof {
                        let ut = u.tag(); let ufn = Int(ut >> 3), uwt = Int(ut & 7)
                        if uwt == 0 { _ = u.varint() }
                        else if uwt == 2 { let s = u.str(); if ufn == 3 { cm.nickname = s } }
                        else { u.skip(wireType: uwt) }
                    }
                } else if fn == 3 { cm.content = String(data: d, encoding: .utf8) ?? "" }
            } else { r.skip(wireType: wt) }
        }
        return cm
    }
}

// MARK: - gzip 解压（照 kq2.java：compress_type=gzip 或 0x1f 0x8b magic → GZIPInputStream）
enum KSGzip {
    /// gzip 解压：剥 RFC1952 头，用 Compression framework 做 raw-deflate inflate。失败返回原数据。
    static func inflate(_ data: Data) -> Data {
        guard data.count > 2, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b else { return data }
        guard let deflate = stripGzipHeader(data) else { return data }
        return rawInflate(deflate) ?? data
    }

    /// 解析 gzip 头（RFC1952），返回 deflate 数据段
    private static func stripGzipHeader(_ data: Data) -> Data? {
        let b = [UInt8](data)
        guard b.count > 10, b[2] == 8 else { return nil }   // method 必须 deflate
        let flags = b[3]
        var p = 10
        if flags & 4 != 0 {  // FEXTRA
            guard p + 2 <= b.count else { return nil }
            let xlen = Int(b[p]) | (Int(b[p + 1]) << 8); p += 2 + xlen
        }
        if flags & 8 != 0 {  // FNAME（null 结尾）
            while p < b.count, b[p] != 0 { p += 1 }; p += 1
        }
        if flags & 16 != 0 { // FCOMMENT
            while p < b.count, b[p] != 0 { p += 1 }; p += 1
        }
        if flags & 2 != 0 { p += 2 }  // FHCRC
        guard p < b.count else { return nil }
        // 去掉尾部 CRC32(4) + ISIZE(4)
        let end = max(p, b.count - 8)
        guard p <= end else { return nil }
        return Data(b[p..<end])
    }

    /// raw-deflate inflate（Compression framework COMPRESSION_ZLIB = raw deflate，无 zlib 头）
    private static func rawInflate(_ src: Data) -> Data? {
        guard !src.isEmpty else { return Data() }
        let srcBytes = [UInt8](src)
        var dst = [UInt8](repeating: 0, count: max(srcBytes.count * 4, 4096))
        var decoded = 0
        let status = dst.withUnsafeMutableBytes { dstPtr -> compression_status in
            srcBytes.withUnsafeBytes { srcPtr -> compression_status in
                let srcPtrBase = srcPtr.bindMemory(to: UInt8.self).baseAddress!
                let dstPtrBase = dstPtr.bindMemory(to: UInt8.self).baseAddress!
                return compression_decode_buffer(
                    dstPtrBase, dst.count,
                    srcPtrBase, src.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard status > 0 else { return nil }
        decoded = status
        return Data(dst.prefix(decoded))
    }
}
