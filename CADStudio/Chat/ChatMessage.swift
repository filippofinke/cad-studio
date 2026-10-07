import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable {
        case user
        case assistant
        case tool
        case thinking
        case system
        case summary
    }

    enum Action: String, Codable {
        case askClaudeToFix
        case openTerminal
        case configureClaude
    }

    var id = UUID()
    var role: Role
    var text: String
    var date = Date()
    var tool: ToolActivity?
    var detail: String?
    var action: Action?
    var attachments: [String]?
}

struct ToolActivity: Codable, Equatable {
    enum State: String, Codable {
        case running
        case succeeded
        case failed
    }

    let toolUseID: String
    let name: String
    var input: String
    var output: String?
    var preview: String?
    var state = State.running
}
