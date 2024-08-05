import Foundation

struct ProjectVersion: Codable, Identifiable {
    let number: Int
    let createdAt: Date
    let prompt: String
    let sessionID: String?

    var id: Int { number }

    enum CodingKeys: String, CodingKey {
        case number
        case createdAt = "created_at"
        case prompt
        case sessionID = "session_id"
    }
}

@MainActor
@Observable
final class VersionHistory {
    private let folder: ProjectFolder
    private(set) var versions: [ProjectVersion]

    init(folder: ProjectFolder) {
        self.folder = folder
        let directories = (try? FileManager.default.contentsOfDirectory(at: folder.versions, includingPropertiesForKeys: nil)) ?? []
        versions = directories
            .compactMap { try? ProjectStore.read(ProjectVersion.self, from: $0.appending(path: "version.json")) }
            .sorted { $0.number < $1.number }
    }

    var nextNumber: Int {
        (versions.last?.number ?? 0) + 1
    }

    func hasChanges(since number: Int?) -> Bool {
        guard let version = versions.first(where: { $0.number == number }) else { return true }
        let saved = try? Data(contentsOf: directory(of: version).appending(path: "model.py"))
        let current = try? Data(contentsOf: folder.modelScript)
        return saved != current
    }

    func record(prompt: String, sessionID: String?) throws -> ProjectVersion {
        let version = ProjectVersion(number: nextNumber, createdAt: .now, prompt: prompt, sessionID: sessionID)
        let directory = directory(of: version)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try copyIfPresent(folder.modelScript, to: directory.appending(path: "model.py"))
        try copyIfPresent(folder.output, to: directory.appending(path: "output"))
        try copyIfPresent(folder.chatFile, to: directory.appending(path: "chat.json"))
        try ProjectStore.write(version, to: directory.appending(path: "version.json"))
        versions.append(version)
        return version
    }

    func restore(_ version: ProjectVersion) throws {
        let directory = directory(of: version)
        try replace(folder.modelScript, with: directory.appending(path: "model.py"))
        try replace(folder.chatFile, with: directory.appending(path: "chat.json"))
        let savedOutput = directory.appending(path: "output")
        for file in try FileManager.default.contentsOfDirectory(at: folder.output, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
        for file in (try? FileManager.default.contentsOfDirectory(at: savedOutput, includingPropertiesForKeys: nil)) ?? [] {
            try FileManager.default.copyItem(at: file, to: folder.output.appending(path: file.lastPathComponent))
        }
    }

    func directory(of version: ProjectVersion) -> URL {
        folder.versions.appending(path: String(version.number), directoryHint: .isDirectory)
    }

    private func copyIfPresent(_ source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func replace(_ destination: URL, with source: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try copyIfPresent(source, to: destination)
    }
}
