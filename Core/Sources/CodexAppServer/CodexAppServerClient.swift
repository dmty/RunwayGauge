import Darwin
import Foundation

public protocol CodexAppServerServing: Sendable {
    func readAccount() async throws -> CodexAccountReadResult
    func readRateLimits() async throws -> CodexRateLimitsReadResult
}

public enum CodexAppServerError: Error, Equatable, Sendable {
    case launchFailed
    case timedOut
    case exitedEarly
    case malformedResponse
    case rpcError(code: Int)
    case missingResult

    public var userMessage: String {
        switch self {
        case .launchFailed: "Could not start Codex."
        case .timedOut: "Codex did not respond in time."
        case .exitedEarly: "Codex app-server exited early."
        case .malformedResponse: "Codex returned an incompatible response."
        case .rpcError: "Codex app-server returned an error."
        case .missingResult: "Codex returned an incomplete response."
        }
    }
}

struct CodexDiagnosticAccumulator: Sendable {
    let limit: Int
    private(set) var data = Data()

    init(limit: Int = 8 * 1_024) { self.limit = limit }

    mutating func append(_ chunk: Data) {
        guard data.count < limit else { return }
        data.append(chunk.prefix(limit - data.count))
    }
}

public struct CodexAppServerClient: CodexAppServerServing, Sendable {
    public let executableURL: URL
    public let timeoutSeconds: TimeInterval
    public let shutdownGraceSeconds: TimeInterval

    public init(
        executableURL: URL,
        timeoutSeconds: TimeInterval = 15,
        shutdownGraceSeconds: TimeInterval = 1
    ) {
        self.executableURL = executableURL
        self.timeoutSeconds = timeoutSeconds
        self.shutdownGraceSeconds = shutdownGraceSeconds
    }

    public func readAccount() async throws -> CodexAccountReadResult {
        try await perform(
            method: "account/read",
            params: AccountReadParams(refreshToken: false),
            result: CodexAccountReadResult.self
        )
    }

    public func readRateLimits() async throws -> CodexRateLimitsReadResult {
        try await perform(
            method: "account/rateLimits/read",
            params: nil as EmptyParams?,
            result: CodexRateLimitsReadResult.self
        )
    }

    private func perform<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        method: String,
        params: Params?,
        result: Result.Type
    ) async throws -> Result {
        let child = try RunningCodexProcess(
            executableURL: executableURL,
            shutdownGraceSeconds: shutdownGraceSeconds
        )
        // ponytail: GCD deadline + stop() — TaskGroup+Task.sleep can't race FileHandle.AsyncBytes
        let gate = OperationDeadline(timeoutSeconds: timeoutSeconds) { child.stop() }
        do {
            return try await withTaskCancellationHandler(
                operation: {
                    do {
                        let value = try await child.exchange(
                            method: method,
                            params: params,
                            result: result
                        )
                        let won = gate.tryComplete()
                        child.stop()
                        guard won else { throw CodexAppServerError.timedOut }
                        return value
                    } catch {
                        if !gate.tryComplete() {
                            throw CodexAppServerError.timedOut
                        }
                        throw error
                    }
                },
                onCancel: {
                    _ = gate.tryComplete()
                    child.stop()
                }
            )
        } catch {
            child.stop()
            throw error
        }
    }
}

/// GCD-backed operation deadline; stop callback unblocks FileHandle reads.
final class OperationDeadline: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var timedOutFlag = false

    var timedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOutFlag
    }

    init(timeoutSeconds: TimeInterval, onTimeout: @escaping @Sendable () -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard !self.finished else {
                self.lock.unlock()
                return
            }
            self.finished = true
            self.timedOutFlag = true
            self.lock.unlock()
            onTimeout()
        }
    }

    /// Claims completion for the exchange path. `false` means the deadline already won.
    @discardableResult
    func tryComplete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if finished { return !timedOutFlag }
        finished = true
        return true
    }
}

private struct ClientInfo: Encodable, Sendable {
    let name = "runway_gauge"
    let title = "RunwayGauge"
    let version = "0.2.0"
}

private struct InitializeParams: Encodable, Sendable { let clientInfo = ClientInfo() }
private struct AccountReadParams: Encodable, Sendable { let refreshToken: Bool }
private struct EmptyParams: Encodable, Sendable {}
private struct ResponseProbe: Decodable {
    let id: Int?
    let method: String?
    let error: CodexRPCError?
}

private struct Request<Params: Encodable>: Encodable {
    let id: Int
    let method: String
    let params: Params?

    private enum CodingKeys: String, CodingKey {
        case id, method, params
    }

    // ponytail: omit `params` key when nil (rateLimits/read), never emit null
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        if let params {
            try container.encode(params, forKey: .params)
        }
    }
}

private struct Notification<Params: Encodable>: Encodable {
    let method: String
    let params: Params
}

private final class RunningCodexProcess: @unchecked Sendable {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let shutdownGraceSeconds: TimeInterval
    private let condition = NSCondition()
    private var diagnostics = CodexDiagnosticAccumulator()
    private var stopState = StopState.idle

    private enum StopState {
        case idle
        case stopping
        case stopped
    }

    init(executableURL: URL, shutdownGraceSeconds: TimeInterval) throws {
        self.shutdownGraceSeconds = shutdownGraceSeconds
        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            throw CodexAppServerError.launchFailed
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.appendDiagnostics(chunk)
        }
    }

    var processIdentifier: Int32 { process.processIdentifier }

    func exchange<Params: Encodable & Sendable, Result: Decodable & Sendable>(
        method: String,
        params: Params?,
        result: Result.Type
    ) async throws -> Result {
        try write(Request(id: 0, method: "initialize", params: InitializeParams()))
        var initialized = false

        for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
            guard let data = line.data(using: .utf8),
                  let probe = try? JSONDecoder().decode(ResponseProbe.self, from: data)
            else { throw CodexAppServerError.malformedResponse }
            guard probe.method == nil, let id = probe.id else { continue }

            if let rpc = probe.error {
                throw CodexAppServerError.rpcError(code: rpc.code)
            }
            if id == 0, !initialized {
                initialized = true
                try write(Notification(method: "initialized", params: EmptyParams()))
                try write(Request(id: 1, method: method, params: params))
                continue
            }
            guard id == 1 else { continue }
            let envelope: CodexRPCResponse<Result>
            do {
                envelope = try JSONDecoder().decode(CodexRPCResponse<Result>.self, from: data)
            } catch {
                throw CodexAppServerError.malformedResponse
            }
            if let rpc = envelope.error {
                throw CodexAppServerError.rpcError(code: rpc.code)
            }
            guard let value = envelope.result else {
                throw CodexAppServerError.missingResult
            }
            // ponytail: no stop() here — caller arbitrates tryComplete first, then stops
            return value
        }
        throw CodexAppServerError.exitedEarly
    }

    private func write<Value: Encodable>(_ value: Value) throws {
        // ponytail: withoutEscapingSlashes so method paths match JSONL peers (fixtures + Codex)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        var data = try encoder.encode(value)
        data.append(0x0A)
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func appendDiagnostics(_ chunk: Data) {
        condition.lock()
        diagnostics.append(chunk)
        condition.unlock()
    }

    func stop() {
        condition.lock()
        switch stopState {
        case .stopped:
            condition.unlock()
            return
        case .stopping:
            while stopState != .stopped {
                condition.wait()
            }
            condition.unlock()
            return
        case .idle:
            stopState = .stopping
            condition.unlock()
        }

        try? stdinPipe.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(shutdownGraceSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        // Reap so isRunning settles after SIGKILL.
        process.waitUntilExit()
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()

        condition.lock()
        stopState = .stopped
        condition.broadcast()
        condition.unlock()
    }
}
