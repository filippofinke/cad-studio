import Foundation

enum CodexRunner {
    static func run(
        _ executable: URL,
        request: ClaudeRequest,
        directory: URL,
        onLine: @escaping ProcessRunner.LineHandler
    ) async throws -> ProcessResult {
        try await ProcessRunner.run(
            executable,
            arguments: arguments(for: request, directory: directory),
            directory: directory,
            environment: await ModelBuilder.toolEnvironment(),
            onOutput: onLine
        )
    }

    static func arguments(for request: ClaudeRequest, directory: URL) -> [String] {
        var arguments = ["exec", "--json", "--skip-git-repo-check", "--sandbox", "workspace-write", "-C", directory.path]
        arguments += ["-c", "approval_policy=\"never\""]
        arguments += ["-c", "developer_instructions=\(tomlString(ClaudeRunner.systemPrompt(for: request)))"]
        if AppSettings.isolatesClaude {
            arguments += ["--ignore-user-config"]
        }
        if let model = AppSettings.codexModel {
            arguments += ["--model", model]
        }
        if let effort = AppSettings.claudeEffort {
            arguments += ["-c", "model_reasoning_effort=\(tomlString(effort))"]
        }
        if let sessionID = request.sessionID {
            arguments += ["resume", sessionID]
        }
        for image in request.images {
            arguments += ["-i", image.path]
        }
        arguments.append(request.prompt)
        return arguments
    }

    private static func tomlString(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    result += String(format: "\\u%04X", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}

struct CodexTranslator {
    private var threadID: String?
    private var lastMessage = ""
    private var errorMessage: String?
    private var started: Set<String> = []
    private var indexes: [String: Int] = [:]

    mutating func events(for line: String) -> [StreamEvent] {
        guard let data = line.data(using: .utf8),
              let event = try? JSONDecoder().decode(JSONValue.self, from: data),
              let type = event["type"]?.string
        else { return [] }
        switch type {
        case "thread.started":
            guard let id = event["thread_id"]?.string else { return [] }
            threadID = id
            return [.started(sessionID: id)]
        case "item.started":
            return started(event["item"])
        case "item.completed":
            return completed(event["item"])
        case "turn.completed":
            return [.finished(TurnResult(subtype: "success", isError: false, text: lastMessage, sessionID: threadID))]
        case "turn.failed":
            let message = event["error"]?["message"]?.string ?? errorMessage ?? "Codex failed"
            return [.finished(TurnResult(subtype: "error", isError: true, text: message, sessionID: threadID))]
        case "error":
            errorMessage = event["message"]?.string
            return []
        default:
            return []
        }
    }

    private mutating func index(for id: String) -> Int {
        if let index = indexes[id] {
            return index
        }
        let index = indexes.count
        indexes[id] = index
        return index
    }

    private mutating func started(_ item: JSONValue?) -> [StreamEvent] {
        guard let item, let id = item["id"]?.string, let type = item["type"]?.string else { return [] }
        switch type {
        case "command_execution":
            started.insert(id)
            return [.assistant([command(id: id, item: item)])]
        case "reasoning":
            return [.blockStarted(index: index(for: id), kind: .thinking), .thinking]
        default:
            return []
        }
    }

    private mutating func completed(_ item: JSONValue?) -> [StreamEvent] {
        guard let item, let id = item["id"]?.string, let type = item["type"]?.string else { return [] }
        switch type {
        case "command_execution":
            var events: [StreamEvent] = started.contains(id) ? [] : [.assistant([command(id: id, item: item)])]
            let failed = item["status"]?.string == "failed" || (item["exit_code"]?.number ?? 0) != 0
            events.append(.toolResults([ToolResultBlock(toolUseID: id, content: item["aggregated_output"]?.string ?? "", isError: failed)]))
            return events
        case "file_change":
            let failed = item["status"]?.string == "failed"
            let changes = item["changes"]?.array ?? []
            return changes.enumerated().flatMap { offset, change -> [StreamEvent] in
                let toolID = "\(id)-\(offset)"
                let path = change["path"]?.string ?? ""
                let name = change["kind"]?.string == "add" ? "Write" : "Edit"
                return [
                    .assistant([.toolUse(id: toolID, name: name, input: .object(["file_path": .string(path)]))]),
                    .toolResults([ToolResultBlock(toolUseID: toolID, content: "", isError: failed)]),
                ]
            }
        case "agent_message":
            let text = item["text"]?.string ?? ""
            guard !text.isEmpty else { return [] }
            lastMessage = text
            return [.blockStarted(index: index(for: id), kind: .text), .assistant([.text(text)])]
        case "reasoning":
            return [.blockStopped(index: index(for: id))]
        case "error":
            errorMessage = item["message"]?.string
            return []
        default:
            return []
        }
    }

    private func command(id: String, item: JSONValue) -> AssistantBlock {
        .toolUse(id: id, name: "Bash", input: .object(["command": .string(Self.unwrapped(item["command"]?.string ?? ""))]))
    }

    private static func unwrapped(_ command: String) -> String {
        for prefix in ["/bin/zsh -lc ", "/bin/bash -lc ", "bash -lc ", "zsh -lc "] where command.hasPrefix(prefix) {
            var inner = String(command.dropFirst(prefix.count))
            if let first = inner.first, first == "'" || first == "\"", inner.last == first, inner.count > 1 {
                inner = String(inner.dropFirst().dropLast())
            }
            return inner
        }
        return command
    }
}
