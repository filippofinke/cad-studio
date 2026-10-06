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

    fileprivate init?(_ raw: RawBlock) {
        guard raw.type == "tool_result", let toolUseID = raw.toolUseID else { return nil }
        self.toolUseID = toolUseID
        content = raw.content?.displayText ?? ""
        isError = raw.isError ?? false
    }
}

struct TurnResult {
    let subtype: String
    let isError: Bool
    let text: String
    let sessionID: String?
}

private struct RawEvent: Decodable {
    let type: String
    let subtype: String?
    let sessionID: String?
    let message: RawMessage?
    let event: RawStreamEvent?
    let result: String?
    let isError: Bool?
    let estimatedTokens: Int?

    enum CodingKeys: String, CodingKey {
        case type, subtype, message, event, result
        case sessionID = "session_id"
        case isError = "is_error"
        case estimatedTokens = "estimated_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        subtype = try? container.decode(String.self, forKey: .subtype)
        sessionID = try? container.decode(String.self, forKey: .sessionID)
        message = try? container.decode(RawMessage.self, forKey: .message)
        event = try? container.decode(RawStreamEvent.self, forKey: .event)
        result = try? container.decode(String.self, forKey: .result)
        isError = try? container.decode(Bool.self, forKey: .isError)
        estimatedTokens = try? container.decode(Int.self, forKey: .estimatedTokens)
    }
}

private struct RawMessage: Decodable {
    let content: [RawBlock]?

    enum CodingKeys: String, CodingKey {
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try? container.decode([RawBlock].self, forKey: .content)
    }
}

private struct RawBlock: Decodable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: JSONValue?
    let toolUseID: String?
    let content: JSONValue?
    let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input, content
        case toolUseID = "tool_use_id"
        case isError = "is_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decode(String.self, forKey: .type)) ?? ""
        text = try? container.decode(String.self, forKey: .text)
        id = try? container.decode(String.self, forKey: .id)
        name = try? container.decode(String.self, forKey: .name)
        input = try? container.decode(JSONValue.self, forKey: .input)
        toolUseID = try? container.decode(String.self, forKey: .toolUseID)
        content = try? container.decode(JSONValue.self, forKey: .content)
        isError = try? container.decode(Bool.self, forKey: .isError)
    }
}

private struct RawStreamEvent: Decodable {
    struct Delta: Decodable {
        let type: String?
        let text: String?
        let partialJSON: String?

        enum CodingKeys: String, CodingKey {
            case type, text
            case partialJSON = "partial_json"
        }
    }

    struct ContentBlock: Decodable {
        let type: String?
        let id: String?
        let name: String?
    }

    let type: String?
    let index: Int?
    let delta: Delta?
    let contentBlock: ContentBlock?

    enum CodingKeys: String, CodingKey {
        case type, index, delta
        case contentBlock = "content_block"
    }
}
