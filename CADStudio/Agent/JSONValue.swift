import Foundation

enum JSONValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { object[key] } else { nil }
    }

    var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    var displayText: String {
        switch self {
        case .string(let value):
            return value
        case .array(let items) where items.allSatisfy({ $0["text"]?.string != nil }):
            return items.compactMap { $0["text"]?.string }.joined(separator: "\n")
        default:
            guard let data = try? JSONSerialization.data(
                withJSONObject: foundationValue,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
            ) else { return "" }
            return String(decoding: data, as: UTF8.self)
        }
    }

    private var foundationValue: Any {
        switch self {
        case .string(let value): value
        case .number(let value): value
        case .bool(let value): value
        case .array(let items): items.map(\.foundationValue)
        case .object(let object): object.mapValues(\.foundationValue)
        case .null: NSNull()
        }
    }
}
