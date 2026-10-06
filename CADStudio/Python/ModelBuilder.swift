import Foundation

enum ModelBuilder {
    static func build(_ folder: ProjectFolder, python: URL) async throws -> ProcessResult {
        try await ProcessRunner.run(
            python,
            arguments: ["model.py"],
            directory: folder.root,
            environment: await toolEnvironment()
        )
    }

    static func toolEnvironment() async -> [String: String] {
        var environment = await ShellEnvironment.shared.environment()
        environment["MPLBACKEND"] = "Agg"
        environment["PYTHONUNBUFFERED"] = "1"
        return environment
    }
}
