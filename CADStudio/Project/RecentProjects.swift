import Foundation

@MainActor
@Observable
final class RecentProjects {
    private static let defaultsKey = "recentProjects"
    private static let limit = 12

    private(set) var urls: [URL]

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        urls = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    func add(_ url: URL) {
        urls.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        urls.insert(url, at: 0)
        urls = Array(urls.prefix(Self.limit))
        save()
    }

    func remove(_ url: URL) {
        urls.removeAll { $0 == url }
        save()
    }

    func clear() {
        urls = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(urls.map(\.path), forKey: Self.defaultsKey)
    }
}
