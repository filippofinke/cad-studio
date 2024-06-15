import Foundation

enum StreamEvent {
    case started(sessionID: String)
    case blockStarted(index: Int, kind: BlockKind)
    case blockStopped(index: Int)
    case textDelta(String)
    case toolInputDelta(index: Int, json: String)
    case thinking
    case thinkingTokens(Int)
    case assistant([AssistantBlock])
    case toolResults([ToolResultBlock])
    case finished(TurnResult)
    case unknown

    init(line: String) {
        guard let raw = try? JSONDecoder().decode(RawEvent.self, from: Data(line.utf8)) else {
            self = .unknown
            return
        }
        self = Self.interpret(raw)
    }

    private static func interpret(_ raw: RawEvent) -> StreamEvent {
        switch raw.type {
        case "system" where raw.subtype == "init":
            guard let sessionID = raw.sessionID else { return .unknown }
            return .started(sessionID: sessionID)
        case "system" where raw.subtype == "thinking_tokens":
            return .thinkingTokens(raw.estimatedTokens ?? 0)
        case "stream_event":
            let index = raw.event?.index ?? 0
            switch (raw.event?.type, raw.event?.delta?.type) {
            case ("content_block_start", _):
                return .blockStarted(index: index, kind: BlockKind(raw.event?.contentBlock))
            case ("content_block_stop", _):
                return .blockStopped(index: index)
            case ("content_block_delta", "text_delta"):
                return .textDelta(raw.event?.delta?.text ?? "")
            case ("content_block_delta", "input_json_delta"):
                return .toolInputDelta(index: index, json: raw.event?.delta?.partialJSON ?? "")
            case ("content_block_delta", "thinking_delta"):
                return .thinking
            default:
                return .unknown
            }
        case "assistant":
            let blocks = (raw.message?.content ?? []).compactMap(AssistantBlock.init)
            return blocks.isEmpty ? .unknown : .assistant(blocks)
        case "user":
            let results = (raw.message?.content ?? []).compactMap(ToolResultBlock.init)
            return results.isEmpty ? .unknown : .toolResults(results)
        case "result":
            return .finished(TurnResult(
                subtype: raw.subtype ?? "",
                isError: raw.isError ?? false,
                text: raw.result ?? "",
                sessionID: raw.sessionID
            ))
        default:
            return .unknown
        }
    }
}

enum BlockKind {
    case text
    case thinking
    case toolUse(id: String, name: String)
    case other

    fileprivate init(_ block: RawStreamEvent.ContentBlock?) {
        switch block?.type {
        case "text":
            self = .text
        case "thinking", "redacted_thinking":
            self = .thinking
        case "tool_use":
            if let id = block?.id, let name = block?.name {
                self = .toolUse(id: id, name: name)
            } else {
                self = .other
            }
        default:
            self = .other
        }
    }
}

enum AssistantBlock {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)

    fileprivate init?(_ raw: RawBlock) {
        switch raw.type {
        case "text":
            guard let text = raw.text else { return nil }
            self = .text(text)
        case "tool_use":
            guard let id = raw.id, let name = raw.name else { return nil }
            self = .toolUse(id: id, name: name, input: raw.input ?? .null)
        default:
            return nil
        }
    }
}

struct ToolResultBlock {
    let toolUseID: String
    let content: String
    let isError: Bool

    init(toolUseID: String, content: String, isError: Bool) {
        self.toolUseID = toolUseID
        self.content = content
        self.isError = isError
    }

    fileprivate init?(_ raw: RawBlock) {
        guard raw.type == "tool_result", let toolUseID = raw.toolUseID else { return nil }
        self.toolUseID = toolUseID
        content = raw.content?.displayText ?? ""
        isError = raw.isError ?? false
    }
}
