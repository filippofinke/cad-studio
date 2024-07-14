import PDFKit
import AppKit

enum Pane: String, Codable, Sendable {
    case chat
    case model3D
    case schematic
}

struct PaneDrag: Equatable {
    let pane: Pane
    var target: Pane?
    var edge: DropEdge?
}

struct PaneFocusRequest: Equatable {
    let pane: Pane
    let id = UUID()
}

enum Activity: Equatable {
    case idle
    case working(String)
    case succeeded(String)
    case failed(String)

    var isWorking: Bool {
        if case .working = self { true } else { false }
    }
}

struct QueuedMessage: Identifiable {
    let id = UUID()
    let text: String
    let attachments: [URL]
}

struct ModelParameter: Identifiable {
    let name: String
    let value: Double

    var id: String { name }
}

struct Issue: Identifiable, Equatable {
    enum Kind {
        case error
        case warning
    }

    let kind: Kind
    let message: String

    var id: String { message }
}

@MainActor
@Observable
final class Project {
    let folder: ProjectFolder
    var metadata: ProjectMetadata
    let chat: ChatViewModel
    let output: ProjectOutput
    let history: VersionHistory
    let viewer = ModelViewerState()
    let schematic = SchematicViewer()
    var isChatVisible = true
    private(set) var layout: LayoutNode
    private(set) var paneDrag: PaneDrag?
    @ObservationIgnored var paneLocator: ((CGPoint) -> (Pane, DropEdge)?)?
    var areParametersVisible = true
    private(set) var queue: [QueuedMessage] = []
    private(set) var isQueuePaused = false
    var activity = Activity.idle {
        didSet {
            if activity.isWorking, !oldValue.isWorking {
                workStartedAt = .now
            } else if !activity.isWorking {
                workStartedAt = nil
            }
        }
    }
    private(set) var workStartedAt: Date?
    var focusRequest: PaneFocusRequest?
    private(set) var buildError: String?
    private(set) var missingOutputs: [String] = []
    @ObservationIgnored private var agent: AgentSession?
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(url: URL) throws {
        folder = ProjectFolder(root: url)
        try ProjectStore.prepare(folder)
        let metadata = (try? ProjectStore.read(ProjectMetadata.self, from: folder.projectFile)) ?? ProjectMetadata()
        self.metadata = metadata
        layout = metadata.layout ?? AppSettings.defaultLayout
        chat = ChatViewModel(file: folder.chatFile)
        output = ProjectOutput(folder: folder)
        history = VersionHistory(folder: folder)
        agent = AgentSession(project: self)
        output.reload()
        watcher = FileWatcher(directory: folder.output) { [weak self] in
            self?.output.reload()
        }
    }

    var name: String { folder.name }

    var isBusy: Bool { activity.isWorking }

    var hasModelScript: Bool { FileManager.default.fileExists(atPath: folder.modelScript.path) }

    var issues: [Issue] {
        var issues: [Issue] = []
        if let buildError {
            issues.append(Issue(kind: .error, message: buildError))
        }
        if !missingOutputs.isEmpty {
            let files = missingOutputs.formatted(.list(type: .and))
            issues.append(Issue(kind: .warning, message: String(localized: "File di output mancanti: \(files)")))
        }
        issues += (output.manifest?.warnings ?? []).map { Issue(kind: .warning, message: $0) }
        if let motionError = output.motionError {
            issues.append(Issue(kind: .warning, message: motionError))
        }
        if let study = output.motionStudy, study.collisionCount > 0 {
            issues.append(Issue(kind: .warning, message: String(localized: "L’animazione ha collisioni tra parti in \(study.collisionCount) fotogrammi")))
        }
        return issues
    }

    var displayedLayout: LayoutNode {
        isChatVisible ? layout : layout.removing(.chat) ?? layout
    }

    func setLayout(_ layout: LayoutNode) {
        self.layout = layout
        isChatVisible = true
        persistLayout()
    }

    func setFraction(_ fraction: Double, at path: [Bool]) {
        guard isChatVisible else { return }
        layout = layout.updatingFraction(at: path, to: fraction)
        metadata.layout = layout
    }

    func dragPane(_ pane: Pane, to screenPoint: CGPoint) {
        let hit = paneLocator?(screenPoint)
        let target = hit?.0 == pane ? nil : hit?.0
        let drag = PaneDrag(pane: pane, target: target, edge: target == nil ? nil : hit?.1)
        if drag != paneDrag {
            paneDrag = drag
        }
    }

    func dropPane() {
        defer { paneDrag = nil }
        guard let paneDrag, let target = paneDrag.target, let edge = paneDrag.edge else { return }
        setLayout(layout.moving(paneDrag.pane, to: edge, of: target))
    }

    private func persistLayout() {
        metadata.layout = layout
        AppSettings.defaultLayout = layout
        save()
    }

    func focus(_ pane: Pane) {
        if pane == .chat {
            isChatVisible = true
            chat.focusInput()
        }
        focusRequest = PaneFocusRequest(pane: pane)
    }

    func sendDraft() {
        if isBusy {
            if let draft = chat.takeDraft() {
                queue.append(QueuedMessage(text: draft.text, attachments: draft.attachments))
            }
            return
        }
        guard PythonEnvironment.shared.isReady else {
            PythonEnvironment.shared.isSetupSheetPresented = !PythonEnvironment.shared.isReady
            return
        }
        guard let draft = chat.takeDraft() else { return }
        send(draft.text, attachments: draft.attachments)
    }

    func send(_ text: String, attachments: [URL] = []) {
        guard !isBusy else { return }
        guard PythonEnvironment.shared.isReady else {
            chat.draft = text
            PythonEnvironment.shared.isSetupSheetPresented = true
            return
        }
        let references = copyReferences(attachments)
        chat.append(ChatMessage(role: .user, text: text, attachments: references.isEmpty ? nil : references))
        chat.save()
        buildError = nil
        activity = .working(String(localized: "\(AgentEngine.current.name) sta lavorando…"))
        let prompt = Self.prompt(text, references: references, missing: missingRequirements)
        task = Task {
            await agent?.run(prompt, images: references.map { folder.root.appending(path: $0) })
        }
    }
