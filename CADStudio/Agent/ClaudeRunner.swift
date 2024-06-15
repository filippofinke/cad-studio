import Foundation

struct ClaudeRequest {
    let prompt: String
    let sessionID: String?
    let projectName: String
    let python: URL
    let environment: String
    let images: [URL]
}

enum ClaudeRunner {
    static func run(
        _ executable: URL,
        request: ClaudeRequest,
        directory: URL,
        onLine: @escaping ProcessRunner.LineHandler
    ) async throws -> ProcessResult {
        try await ProcessRunner.run(
            executable,
            arguments: arguments(for: request),
            directory: directory,
            environment: await ModelBuilder.toolEnvironment(),
            onOutput: onLine
        )
    }

    static func arguments(for request: ClaudeRequest) -> [String] {
        var arguments = ["-p", request.prompt]
        if AppSettings.usesStreamingOutput {
            arguments += ["--output-format", "stream-json", "--verbose", "--include-partial-messages"]
        } else {
            arguments += ["--output-format", "json"]
        }
        arguments += ["--append-system-prompt", systemPrompt(for: request)]
        arguments += ["--permission-mode", "acceptEdits"]
        arguments += ["--allowedTools"] + allowedTools(python: request.python)
        if AppSettings.isolatesClaude {
            arguments += ["--strict-mcp-config", "--setting-sources", "project,local"]
        }
        if let sessionID = request.sessionID {
            arguments += ["--resume", sessionID, "--fork-session"]
        }
        if let model = AppSettings.claudeModel {
            arguments += ["--model", model]
        }
        if let effort = AppSettings.claudeEffort {
            arguments += ["--effort", effort]
        }
        return arguments
    }
