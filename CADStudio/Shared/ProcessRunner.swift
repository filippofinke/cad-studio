import Foundation
import Synchronization

struct ProcessResult: Sendable {
    let status: Int32
    let output: String
    let errorOutput: String
    let wasInterrupted: Bool

    var succeeded: Bool { status == 0 && !wasInterrupted }
}

enum ProcessRunner {
    typealias LineHandler = @MainActor @Sendable (String) -> Void

    static func run(
        _ executable: URL,
        arguments: [String] = [],
        directory: URL? = nil,
        environment: [String: String]? = nil,
        onOutput: LineHandler? = nil,
        onError: LineHandler? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        if let environment {
            process.environment = environment
        }
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        let (exitCodes, exitContinuation) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }

        try process.run()
        let pid = process.processIdentifier
        RunningProcesses.shared.insert(pid)
        defer { RunningProcesses.shared.remove(pid) }

        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        return await withTaskCancellationHandler {
            async let output = readLines(from: outputHandle, onLine: onOutput)
            async let errorOutput = readLines(from: errorHandle, onLine: onError)
            var status: Int32 = -1
            for await code in exitCodes {
                status = code
            }
            return await ProcessResult(
                status: status,
                output: output,
                errorOutput: errorOutput,
                wasInterrupted: Task.isCancelled
            )
        } onCancel: {
            RunningProcesses.shared.interrupt(pid)
        }
    }

    private static func readLines(from handle: FileHandle, onLine: LineHandler?) async -> String {
        var text = ""
        for await line in lines(from: handle) {
            text += line + "\n"
            if let onLine {
                await onLine(line)
            }
        }
        return text
    }

    private static func lines(from handle: FileHandle) -> AsyncStream<String> {
        AsyncStream { continuation in
            let buffer = LineBuffer()
            handle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    if let remainder = buffer.remainder() {
                        continuation.yield(remainder)
                    }
                    continuation.finish()
                } else {
                    buffer.append(data).forEach { continuation.yield($0) }
                }
            }
        }
    }
}

private final class LineBuffer: @unchecked Sendable {
    private var pending = Data()

    func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            lines.append(decode(pending[pending.startIndex..<newline]))
            pending.removeSubrange(pending.startIndex...newline)
        }
        return lines
    }

    func remainder() -> String? {
        guard !pending.isEmpty else { return nil }
        defer { pending = Data() }
        return decode(pending)
    }

    private func decode(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
    }
}

final class RunningProcesses: Sendable {
    static let shared = RunningProcesses()

    private let identifiers = Mutex<Set<pid_t>>([])

    func insert(_ pid: pid_t) {
        identifiers.withLock { _ = $0.insert(pid) }
    }

    func remove(_ pid: pid_t) {
        identifiers.withLock { _ = $0.remove(pid) }
    }

    func interrupt(_ pid: pid_t) {
        kill(pid, SIGINT)
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            if self.identifiers.withLock({ $0.contains(pid) }) {
                kill(pid, SIGTERM)
            }
        }
    }

    func terminateAll() {
        for pid in identifiers.withLock({ $0 }) {
            kill(pid, SIGTERM)
        }
    }
}
