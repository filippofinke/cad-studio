import Foundation

actor ShellEnvironment {
    static let shared = ShellEnvironment()

    private var cachedPath: String?

    private static let fallbackDirectories = [
        "~/.local/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ].map { NSString(string: $0).expandingTildeInPath }

    func path() async -> String {
        if let cachedPath {
            return cachedPath
        }
        let loginPath = await loginShellOutput("echo $PATH") ?? ""
        var directories = loginPath.split(separator: ":").map(String.init)
        for directory in Self.fallbackDirectories where !directories.contains(directory) {
            directories.append(directory)
        }
        let path = directories.joined(separator: ":")
        cachedPath = path
        return path
    }

    func environment() async -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = await path()
        return environment
    }

    func locate(_ command: String) async -> URL? {
        if let output = await loginShellOutput("command -v \(command)"), output.hasPrefix("/") {
            return URL(filePath: output)
        }
        for directory in await path().split(separator: ":") {
            let candidate = URL(filePath: String(directory)).appending(path: command)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func loginShellOutput(_ command: String) async -> String? {
        let result = try? await ProcessRunner.run(URL(filePath: "/bin/zsh"), arguments: ["-lc", command])
        guard let result, result.status == 0 else { return nil }
        let lastLine = result.output
            .split(separator: "\n")
            .last
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return lastLine?.isEmpty == false ? lastLine : nil
    }
}
