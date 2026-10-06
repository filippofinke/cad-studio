import Foundation

@MainActor
@Observable
final class ClaudeLocator {
    enum State: Equatable {
        case unknown
        case checking
        case found(URL, version: String)
        case missing
    }

    static let shared = ClaudeLocator()

    private static let knownPaths = [
        "~/.claude/local/claude",
        "~/.local/bin/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "~/.npm-global/bin/claude",
    ].map { URL(filePath: NSString(string: $0).expandingTildeInPath) }

    var state = State.unknown
    var isMissingSheetPresented = false

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
        if let custom = AppSettings.claudePath {
            urls.append(custom)
        }
        if let fromShell = await ShellEnvironment.shared.locate("claude") {
            urls.append(fromShell)
        }
        urls += Self.knownPaths
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
