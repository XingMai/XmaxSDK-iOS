import Foundation

/// 将房间 JSON 信令拆成与服务端一致的声网 DataStream 分片。
enum RtcMessageCodec {
    static func encode(_ message: String) throws -> [Data] {
        let bytes = Data(message.utf8)
        guard !bytes.isEmpty, bytes.count <= 256 * 1024 else {
            throw XmaxError(code: .invalidConfiguration, message: "RTC room message must contain between 1 and 262144 bytes")
        }
        if bytes.count <= 800 { return [bytes] }

        var chunks: [String] = []
        var chunk = ""
        var length = 0
        for scalar in message.unicodeScalars {
            let value = String(scalar)
            let encoded = try JSONEncoder().encode(value).count - 2
            if length + encoded > 600 {
                chunks.append(chunk)
                chunk = ""
                length = 0
            }
            chunk += value
            length += encoded
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        guard chunks.count <= 512 else {
            throw XmaxError(code: .invalidConfiguration, message: "RTC room message contains too many fragments")
        }

        let eventID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return try chunks.enumerated().map { index, chunk in
            try JSONEncoder().encode(Fragment(eventId: eventID, index: index, count: chunks.count, data: chunk))
        }
    }

    private struct Fragment: Encodable {
        let event = "__agora_chunk__"
        let eventId: String
        let index: Int
        let count: Int
        let data: String
    }
}

/// 串行发送整组信令，并限制 DataStream 每秒的包数和字节数。
final class RtcMessageQueue: @unchecked Sendable {

    // 发送依赖
    private let send: @Sendable (Data) throws -> Void
    private let onFailure: @Sendable (XmaxError) -> Void
    private let limiter = RateLimiter()

    // 并发状态
    private let lock = NSLock()
    private var closed = false
    private var tasks: [UUID: Task<Void, any Error>] = [:]
    private var lastTask: Task<Void, any Error>?

    init(send: @escaping @Sendable (Data) throws -> Void, onFailure: @escaping @Sendable (XmaxError) -> Void) {
        self.send = send
        self.onFailure = onFailure
    }

    func enqueue(_ message: String) throws {
        let packets = try RtcMessageCodec.encode(message)
        try lock.withLock {
            guard !closed else { throw CancellationError() }
            guard tasks.count < 64 else {
                throw XmaxError(code: .rtcError, message: "RTC room message queue is full")
            }

            let previous = lastTask
            let id = UUID()
            let task = Task { [self] in
                defer { _ = lock.withLock { tasks.removeValue(forKey: id) } }
                do {
                    try await previous?.value
                    for packet in packets {
                        try await limiter.wait(byteCount: packet.count)
                        try Task.checkCancellation()
                        try send(packet)
                    }
                } catch {
                    if !Task.isCancelled, !lock.withLock({ closed }) {
                        onFailure(XmaxError.from(error))
                    }
                    throw error
                }
            }
            tasks[id] = task
            lastTask = task
        }
    }

    func flush() async throws {
        let pending = lock.withLock { lastTask }
        let completion = AsyncThrowingStream<Void, any Error> { continuation in
            let observer = Task {
                do {
                    try await pending?.value
                    continuation.yield()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in observer.cancel() }
        }
        for try await _ in completion {}
        try Task.checkCancellation()
    }

    func close() {
        lock.withLock {
            closed = true
            tasks.values.forEach { $0.cancel() }
            tasks.removeAll()
            lastTask = nil
        }
    }
}

private extension RtcMessageQueue {
    actor RateLimiter {
        var sent: [(time: UInt64, bytes: Int)] = []

        func wait(byteCount: Int) async throws {
            while true {
                try Task.checkCancellation()
                let now = DispatchTime.now().uptimeNanoseconds
                sent.removeAll { now - $0.time >= 1000000000 }
                if sent.count < 28, sent.reduce(0, { $0 + $1.bytes }) + byteCount <= 5800 {
                    sent.append((now, byteCount))
                    return
                }
                let elapsed = now - sent[0].time
                try await Task.sleep(nanoseconds: 1000000000 - elapsed)
            }
        }
    }
}
