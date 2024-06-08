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
