import Foundation

enum StreamEvent {
    case started(sessionID: String)
    case blockStarted
    case textDelta(String)
    case thinking
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
        case "stream_event":
            switch (raw.event?.type, raw.event?.delta?.type) {
            case ("content_block_start", _):
                return .blockStarted
            case ("content_block_delta", "text_delta"):
                return .textDelta(raw.event?.delta?.text ?? "")
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

    enum CodingKeys: String, CodingKey {
        case type, subtype, message, event, result
        case sessionID = "session_id"
        case isError = "is_error"
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
    }

    let type: String?
    let delta: Delta?
}
