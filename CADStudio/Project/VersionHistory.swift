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
