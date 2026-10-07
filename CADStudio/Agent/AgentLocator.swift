import Foundation

enum AgentEngine: String, CaseIterable, Sendable {
    case claude
    case codex

    static var current: AgentEngine {
        AgentEngine(rawValue: UserDefaults.standard.string(forKey: AppSettings.agentEngineKey) ?? "") ?? .claude
    }

    var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    var command: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        }
    }

    var loginCommand: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex login"
        }
    }

    var installURL: URL {
        switch self {
        case .claude: URL(string: "https://claude.com/claude-code")!
        case .codex: URL(string: "https://developers.openai.com/codex/cli")!
        }
    }

    var pathKey: String {
        switch self {
        case .claude: AppSettings.claudePathKey
        case .codex: AppSettings.codexPathKey
        }
    }

    var modelKey: String {
        switch self {
        case .claude: AppSettings.claudeModelKey
        case .codex: AppSettings.codexModelKey
        }
    }

    fileprivate var knownPaths: [URL] {
        let paths: [String] = switch self {
        case .claude:
            ["~/.claude/local/claude", "~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "~/.npm-global/bin/claude"]
        case .codex:
            ["~/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex", "~/.npm-global/bin/codex", "~/.cargo/bin/codex"]
        }
        return paths.map { URL(filePath: NSString(string: $0).expandingTildeInPath) }
    }
}

@MainActor
@Observable
final class AgentLocator {
    enum State: Equatable {
        case unknown
        case checking
        case found(URL, version: String)
        case missing
    }

    static let claude = AgentLocator(engine: .claude)
    static let codex = AgentLocator(engine: .codex)

    static var current: AgentLocator {
        locator(for: AgentEngine.current)
    }

    static func locator(for engine: AgentEngine) -> AgentLocator {
        switch engine {
        case .claude: claude
        case .codex: codex
        }
    }

    let engine: AgentEngine
    var state = State.unknown
    var isMissingSheetPresented = false

    private init(engine: AgentEngine) {
        self.engine = engine
    }

    var executable: URL? {
        if case .found(let url, _) = state { url } else { nil }
    }

    func resolve() async -> URL? {
        if let executable {
            return executable
        }
        await locate()
        return executable
    }

    func locate() async {
        state = .checking
        for candidate in await candidates() {
            if let version = await version(of: candidate) {
                state = .found(candidate, version: version)
                return
            }
        }
        state = .missing
    }

    private func candidates() async -> [URL] {
        var urls: [URL] = []
        if let custom = UserDefaults.standard.string(forKey: engine.pathKey).flatMap({ $0.isEmpty ? nil : $0 }) {
            urls.append(URL(filePath: NSString(string: custom).expandingTildeInPath))
        }
        if let fromShell = await ShellEnvironment.shared.locate(engine.command) {
            urls.append(fromShell)
        }
        urls += engine.knownPaths
        return urls.filter { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func version(of executable: URL) async -> String? {
        let environment = await ShellEnvironment.shared.environment()
        guard let result = try? await ProcessRunner.run(executable, arguments: ["--version"], environment: environment),
              result.status == 0
        else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
