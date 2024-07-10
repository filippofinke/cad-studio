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
