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

    private func copyReferences(_ urls: [URL]) -> [String] {
        guard !urls.isEmpty else { return [] }
        try? FileManager.default.createDirectory(at: folder.references, withIntermediateDirectories: true)
        let stamp = Int(Date.now.timeIntervalSince1970)
        return urls.enumerated().compactMap { index, url in
            let name = "\(stamp)-\(index + 1)-\(url.lastPathComponent)"
            guard (try? FileManager.default.copyItem(at: url, to: folder.references.appending(path: name))) != nil else { return nil }
            return "references/\(name)"
        }
    }

    private var missingRequirements: [String] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.modelScript.path) else { return [] }
        var missing = folder.expectedOutputs.filter { !manager.fileExists(atPath: $0.path) }.map(\.lastPathComponent)
        if !manager.fileExists(atPath: folder.plate.path) {
            missing.append("plate.3mf (print plate)")
        }
        if output.parts.count > 1, !manager.fileExists(atPath: folder.output.appending(path: "schematic-2.svg").path) {
            missing.append("one drawing page per piece (schematic-2.svg, …) with the parts list on page 1")
        }
        if let manifest = output.manifest {
            if output.drawingPages.count > 1, manifest.drawings.isEmpty {
                missing.append("`drawings` in manifest.json (page titles)")
            }
            if manifest.bed == nil, AppSettings.printerModel != nil {
                missing.append("`bed` in manifest.json (bed size of the user's printer)")
            }
        }
        if output.drawingPages.count > 1, (PDFDocument(url: folder.pdf)?.pageCount ?? 0) < output.drawingPages.count {
            missing.append("schematic.pdf with all drawing pages in one file (PdfPages)")
        }
        return missing
    }

    private static func prompt(_ text: String, references: [String], missing: [String]) -> String {
        var prompt = text.isEmpty && !references.isEmpty ? "Create a model based on the attached files." : text
        if !references.isEmpty {
            let list = references.map { "- \($0)" }.joined(separator: "\n")
            prompt += "\n\nAttached reference files:\n\(list)"
        }
        if !missing.isEmpty {
            let list = missing.map { "- \($0)" }.joined(separator: "\n")
            prompt += "\n\nNote from CAD Studio: model.py does not produce these required outputs yet. Add them in this turn as well, following your instructions:\n\(list)"
        }
        return prompt
    }

    func askClaudeToFix(_ traceback: String) {
        send(String(localized: "L’esecuzione di model.py non riesce con questo errore. Correggi lo script:\n```\n\(traceback)\n```"))
    }

    func agentDidFinish(_ failure: Activity?) {
        chat.save()
        save()
        output.reload()
        missingOutputs = output.missingFiles
        if let failure {
            activity = failure
        } else if missingOutputs.isEmpty {
            activity = .succeeded(String(localized: "Modello generato"))
            recordVersion(prompt: chat.messages.last { $0.role == .user }?.text ?? "")
        } else {
            activity = .succeeded(String(localized: "Risposta completata"))
        }
        continueQueue(succeeded: failure == nil)
    }

    func removeQueued(_ message: QueuedMessage) {
        queue.removeAll { $0.id == message.id }
        if queue.isEmpty {
            isQueuePaused = false
        }
    }

    func sendQueuedNow() {
        isQueuePaused = false
        sendNextQueued()
    }

    private func continueQueue(succeeded: Bool) {
        guard !queue.isEmpty else { return }
        guard succeeded else {
            isQueuePaused = true
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            sendNextQueued()
        }
    }

    private func sendNextQueued() {
        guard !isBusy, !isQueuePaused, !queue.isEmpty, PythonEnvironment.shared.isReady else { return }
        let next = queue.removeFirst()
        send(next.text, attachments: next.attachments)
    }

    func restore(_ version: ProjectVersion) {
        guard !isBusy else { return }
        do {
            try history.restore(version)
            metadata.sessionID = version.sessionID
            metadata.currentVersion = version.number
            save()
            chat.reload()
            output.reload()
            buildError = nil
            missingOutputs = []
            activity = .succeeded(String(localized: "Versione \(version.number) ripristinata"))
        } catch {
            activity = .failed(String(localized: "Impossibile ripristinare la versione \(version.number)"))
            buildError = error.localizedDescription
        }
    }

    private func recordVersion(prompt: String) {
        guard history.hasChanges(since: metadata.currentVersion) else { return }
        chat.append(ChatMessage(role: .summary, text: String(localized: "Versione \(history.nextNumber)"), detail: String(history.nextNumber)))
        chat.save()
        do {
            let version = try history.record(prompt: prompt, sessionID: metadata.sessionID)
            metadata.currentVersion = version.number
            save()
        } catch {
            buildError = error.localizedDescription
        }
    }

    var parameters: [ModelParameter] {
        output.parameters
    }
