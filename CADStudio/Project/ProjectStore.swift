import Foundation

struct ProjectMetadata: Codable {
    var sessionID: String?
    var currentVersion: Int?
    var createdAt = Date()
    var updatedAt = Date()
    var appVersion = Bundle.main.shortVersion
    var layout: LayoutNode?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case currentVersion = "current_version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case appVersion = "app_version"
        case layout
    }
}

enum ProjectError: LocalizedError {
    case alreadyExists(String)
    case notAFolder(String)

    var errorDescription: String? {
        switch self {
        case .alreadyExists(let name):
            String(localized: "Esiste già una cartella chiamata “\(name)” in questa posizione.")
        case .notAFolder(let path):
            String(localized: "“\(path)” non è una cartella.")
        }
    }
}

enum ProjectStore {
    static func create(named name: String, in parent: URL) throws -> URL {
        let root = parent.appending(path: name, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: root.path) else {
            throw ProjectError.alreadyExists(name)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try prepare(ProjectFolder(root: root))
        return root
    }

    static func prepare(_ folder: ProjectFolder) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectError.notAFolder(folder.root.path)
        }
        for directory in [folder.output, folder.support, folder.logs] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: folder.projectFile.path) {
            try write(ProjectMetadata(), to: folder.projectFile)
        }
    }

    static func read<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    static func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
