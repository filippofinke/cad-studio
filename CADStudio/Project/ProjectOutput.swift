import Foundation

@MainActor
@Observable
final class ProjectOutput {
    private let folder: ProjectFolder
    private(set) var mesh: TriangleMesh?
    private(set) var parts: [NamedMesh] = []
    private(set) var plateParts: [NamedMesh] = []
    private(set) var plateID = UUID()
    private(set) var drawingPages: [DrawingPage] = []
    private(set) var motionStudy: MotionStudy?
    private(set) var motionError: String?
    private(set) var meshID = UUID()
    private(set) var meshError: String?
    private(set) var manifest: Manifest?
    private(set) var parameters: [ModelParameter] = []
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
        let pages = discoverDrawingPages()
        let pagesChanged = pages.map(hasChanged).contains(true) || pages.map(\.self) != drawingPages.map(\.file)
        let pngChanged = hasChanged(folder.png)
        if pagesChanged || pngChanged {
            schematicRevision = UUID()
        }
        if hasChanged(folder.manifest) {
            manifest = try? ProjectStore.read(Manifest.self, from: folder.manifest)
            parameters = orderedParameters()
        }
        let titledPages = pages.enumerated().map { index, file in
            let title = manifest?.drawings.first { $0.file == file.lastPathComponent }?.title
            return DrawingPage(file: file, title: title ?? String(localized: "Pagina \(index + 1)"))
        }
        if titledPages != drawingPages {
            drawingPages = titledPages
        }
        if hasChanged(folder.plate) {
            loadPlate()
        }
        if hasChanged(folder.animation) {
            loadMotionStudy()
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

    private func discoverDrawingPages() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder.output, includingPropertiesForKeys: nil)) ?? []
        let extra = files
            .compactMap { file -> (Int, URL)? in
                let name = file.deletingPathExtension().lastPathComponent
                guard file.pathExtension == "svg", name.hasPrefix("schematic-"), let number = Int(name.dropFirst("schematic-".count)) else {
                    return nil
                }
                return (number, file)
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
        return (FileManager.default.fileExists(atPath: folder.svg.path) ? [folder.svg] : []) + extra
    }

    private func loadPlate() {
        let plate = folder.plate
        guard FileManager.default.fileExists(atPath: plate.path) else {
            plateParts = []
            plateID = UUID()
            return
        }
        Task {
            let model = await Task.detached(priority: .userInitiated) {
                try? ThreeMFParser.parse(plate)
            }.value
            plateParts = model?.parts ?? []
            plateID = UUID()
        }
    }

    private func orderedParameters() -> [ModelParameter] {
        let values = manifest?.parameters ?? [:]
        let script = (try? String(contentsOf: folder.modelScript, encoding: .utf8)) ?? ""
        return values
            .map { ModelParameter(name: $0.key, value: $0.value) }
            .sorted { first, second in
                let firstIndex = script.range(of: first.name)?.lowerBound ?? script.endIndex
                let secondIndex = script.range(of: second.name)?.lowerBound ?? script.endIndex
                return firstIndex == secondIndex ? first.name < second.name : firstIndex < secondIndex
            }
    }

    private func loadMotionStudy() {
        guard FileManager.default.fileExists(atPath: folder.animation.path) else {
            motionStudy = nil
            motionError = nil
            return
        }
        do {
            let study = try JSONDecoder().decode(MotionStudy.self, from: Data(contentsOf: folder.animation))
            motionStudy = study.frames.count > 1 ? study : nil
            motionError = nil
        } catch {
            motionStudy = nil
            motionError = String(localized: "animation.json non è valido: \(error.localizedDescription)")
        }
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
                mesh = loaded.mesh
                parts = loaded.parts
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
            comparisonMesh = try? result.get().mesh
            comparisonID = UUID()
        }
    }

    private nonisolated static func parseMesh(threeMF: URL, stl: URL) -> Result<LoadedModel, Error> {
        if let model = try? ThreeMFParser.parse(threeMF) {
            return .success(model)
        }
        return Result { LoadedModel(mesh: try STLParser.parse(stl), parts: []) }
    }
}

struct DrawingPage: Equatable {
    let file: URL
    let title: String
}
