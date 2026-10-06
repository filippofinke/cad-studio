import Foundation

struct ClaudeRequest {
    let prompt: String
    let sessionID: String?
    let projectName: String
    let python: URL
    let environment: String
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

    static func quotedPython(_ python: URL) -> String {
        python.path.contains(" ") ? "\"\(python.path)\"" : python.path
    }

    private static func allowedTools(python: URL) -> [String] {
        guard AppSettings.usesRestrictedBash else {
            return ["Read,Write,Edit,Glob,Grep,Bash"]
        }
        let interpreter = quotedPython(python)
        let readOnlyCommands = ["ls", "cat", "head", "tail", "wc", "file", "test", "pwd", "stat"]
        return ["Read", "Write", "Edit", "Glob", "Grep", "Bash(\(interpreter):*)"]
            + readOnlyCommands.map { "Bash(\($0):*)" }
    }

    private static func systemPrompt(for request: ClaudeRequest) -> String {
        guard let url = Bundle.main.url(forResource: "CADSystemPrompt", withExtension: "md"),
              let template = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return template
            .replacingOccurrences(of: "{{PYTHON}}", with: quotedPython(request.python))
            .replacingOccurrences(of: "{{PROJECT_NAME}}", with: request.projectName)
            .replacingOccurrences(of: "{{DATE}}", with: Date.now.formatted(date: .numeric, time: .omitted))
            .replacingOccurrences(of: "{{UNITS}}", with: AppSettings.measurementUnit.promptName)
            .replacingOccurrences(of: "{{PRINTER}}", with: printerDescription())
            .replacingOccurrences(of: "{{PRINTING_GUIDELINES}}", with: AppSettings.printerType.promptGuidelines)
            .replacingOccurrences(of: "{{ENVIRONMENT}}", with: request.environment)
    }

    private static func printerDescription() -> String {
        guard let model = AppSettings.printerModel else {
            return "not specified"
        }
        return model
    }
}
