import Foundation

@MainActor
@Observable
final class ProjectOutput {
    private let folder: ProjectFolder
    private(set) var mesh: TriangleMesh?
    private(set) var meshID = UUID()
    private(set) var meshError: String?
    private(set) var manifest: Manifest?
    private(set) var hasSVG = false
    private(set) var hasPNG = false
    private(set) var hasThreeMF = false
    private(set) var schematicRevision = UUID()
    private(set) var comparisonMesh: TriangleMesh?
    private(set) var comparisonManifest: Manifest?
    private(set) var comparisonID: UUID?
    private var modificationDates: [URL: Date] = [:]
    private var loadTask: Task<Void, Never>?

    init(folder: ProjectFolder) {
        self.folder = folder
    }

    var missingFiles: [String] {
        folder.expectedOutputs
            .filter { !FileManager.default.fileExists(atPath: $0.path) }
            .map(\.lastPathComponent)
    }

    func reload() {
        hasSVG = FileManager.default.fileExists(atPath: folder.svg.path)
        hasPNG = FileManager.default.fileExists(atPath: folder.png.path)
        hasThreeMF = FileManager.default.fileExists(atPath: folder.threeMF.path)
        let svgChanged = hasChanged(folder.svg)
        let pngChanged = hasChanged(folder.png)
        if svgChanged || pngChanged {
            schematicRevision = UUID()
        }
        if hasChanged(folder.manifest) {
            manifest = try? ProjectStore.read(Manifest.self, from: folder.manifest)
        }
        let threeMFChanged = hasChanged(folder.threeMF)
        let stlChanged = hasChanged(folder.stl)
        if threeMFChanged || stlChanged {
            loadMesh()
        }
    }

    private func hasChanged(_ url: URL) -> Bool {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let previous = modificationDates[url]
        modificationDates[url] = date
        return date != previous
    }

    private func loadMesh() {
        let threeMF = folder.threeMF
        let stl = folder.stl
        guard hasThreeMF || FileManager.default.fileExists(atPath: stl.path) else {
            mesh = nil
            meshError = nil
            return
        }
        loadTask?.cancel()
        loadTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.parseMesh(threeMF: threeMF, stl: stl)
            }.value
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let loaded):
                mesh = loaded
                meshID = UUID()
                meshError = nil
            case .failure(let error):
                meshError = error.localizedDescription
            }
        }
    }

    func loadComparison(from directory: URL?) {
        guard let directory else {
            comparisonMesh = nil
            comparisonManifest = nil
            comparisonID = nil
            return
        }
        let output = directory.appending(path: "output")
        comparisonManifest = try? ProjectStore.read(Manifest.self, from: output.appending(path: "manifest.json"))
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.parseMesh(threeMF: output.appending(path: "model.3mf"), stl: output.appending(path: "model.stl"))
            }.value
            comparisonMesh = try? result.get()
            comparisonID = UUID()
        }
    }

    private nonisolated static func parseMesh(threeMF: URL, stl: URL) -> Result<TriangleMesh, Error> {
        if let mesh = try? ThreeMFParser.parse(threeMF) {
            return .success(mesh)
        }
        return Result { try STLParser.parse(stl) }
    }
}
