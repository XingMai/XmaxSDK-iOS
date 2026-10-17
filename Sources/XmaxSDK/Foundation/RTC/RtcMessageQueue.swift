//
//  RtcMessageQueue.swift
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-iOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Foundation

/// 将房间 JSON 信令拆成与服务端一致的声网 DataStream 分片。
enum RtcMessageCodec {
    /// 将 UTF-8 信令编码为单包或可重组的 JSON 分片。
    ///
    /// - Parameter message: 完整房间信令。
    /// - Returns: 按发送顺序排列的数据包。
    /// - Throws: 信令为空、超过大小或分片数限制，以及 JSON 编码失败时抛出错误。
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

    /// 封装一条大信令的分片内容及重组信息。
    private struct Fragment: Encodable {

        // 分片标识
        let event = "__agora_chunk__"
        let eventId: String


        // 分片顺序
        let index: Int
        let count: Int


        // 分片内容
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
    private var lastFailureIsFatal = true

    /// 创建串行且限速的房间信令队列。
    ///
    /// - Parameters:
    ///   - send: 实际提交单个数据包的同步操作。
    ///   - onFailure: 接收需要上报的异步发送错误。
    init(send: @escaping @Sendable (Data) throws -> Void, onFailure: @escaping @Sendable (XmaxError) -> Void) {
        self.send = send
        self.onFailure = onFailure
    }

    /// 将一条完整信令加入串行发送队列。
    ///
    /// - Parameters:
    ///   - message: 待发送的完整信令。
    ///   - reportFailure: 异步发送失败时是否通知故障回调。
    /// - Returns: 可独立等待当前信令发送结果的任务。
    /// - Throws: 信令编码失败、队列已关闭或队列已满时抛出错误。
    @discardableResult
    func enqueue(_ message: String, reportFailure: Bool = true) throws -> Task<Void, any Error> {
        let packets = try RtcMessageCodec.encode(message)
        return try lock.withLock {
            guard !closed else { throw CancellationError() }
            guard tasks.count < 64 else {
                throw XmaxError(code: .rtcError, message: "RTC room message queue is full")
            }

            let previous = lastTask
            let previousFailureIsFatal = lastFailureIsFatal
            let id = UUID()
            let task = Task { [self] in
                defer { _ = lock.withLock { tasks.removeValue(forKey: id) } }
                do {
                    if previousFailureIsFatal {
                        try await previous?.value
                    } else {
                        _ = try? await previous?.value
                    }
                    for packet in packets {
                        try await limiter.wait(byteCount: packet.count)
                        try Task.checkCancellation()
                        try send(packet)
                    }
                } catch {
                    if !Task.isCancelled, !lock.withLock({ closed }) {
                        if reportFailure {
                            onFailure(XmaxError.from(error))
                        } else {
                            XmaxLogger.rtc.warn(message: "发送配置失败 (Failed to Send Configuration)\n└─ \(ErrorMessageFormatter.format(error))")
                        }
                    }
                    throw error
                }
            }
            tasks[id] = task
            lastTask = task
            lastFailureIsFatal = reportFailure
            return task
        }
    }

    /// 等待调用时已入队的信令发送完成。
    ///
    /// - Throws: 发送失败或等待被取消时抛出错误。
    func flush() async throws {
        let pending = lock.withLock { lastTask }
        try await Self.waitForCompletion(of: pending)
    }

    /// 等待指定信令完成，不受后续入队消息影响。
    ///
    /// - Parameter pending: 需要等待的发送任务；`nil` 表示无需等待。
    /// - Throws: 指定任务失败或当前等待取消时抛出错误。
    static func waitForCompletion(of pending: Task<Void, any Error>?) async throws {
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

    /// 关闭发送队列并取消尚未完成的信令。
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
    /// 按滑动时间窗口限制信令包数与总字节数。
    actor RateLimiter {

        // 发送窗口
        var sent: [(time: UInt64, bytes: Int)] = []

        /// 等待发送窗口有足够的包数和字节预算。
        ///
        /// - Parameter byteCount: 本次待发送的数据包字节数。
        /// - Throws: 等待被取消时抛出取消错误。
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
