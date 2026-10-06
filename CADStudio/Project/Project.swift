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
        guard !isBusy, PythonEnvironment.shared.isReady else {
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
        activity = .working(String(localized: "Claude sta lavorando…"))
        let prompt = Self.prompt(text, references: references)
        task = Task {
            await agent?.run(prompt)
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

    private static func prompt(_ text: String, references: [String]) -> String {
        guard !references.isEmpty else { return text }
        let request = text.isEmpty ? "Create a model based on the attached images." : text
        let list = references.map { "- \($0)" }.joined(separator: "\n")
        return "\(request)\n\nAttached reference images (open them with the Read tool):\n\(list)"
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
        let values = output.manifest?.parameters ?? [:]
        let script = (try? String(contentsOf: folder.modelScript, encoding: .utf8)) ?? ""
        return values
            .map { ModelParameter(name: $0.key, value: $0.value) }
            .sorted { first, second in
                let firstIndex = script.range(of: first.name)?.lowerBound ?? script.endIndex
                let secondIndex = script.range(of: second.name)?.lowerBound ?? script.endIndex
                return firstIndex == secondIndex ? first.name < second.name : firstIndex < secondIndex
            }
    }

    func setParameter(_ name: String, to value: Double) {
        guard !isBusy, let script = try? String(contentsOf: folder.modelScript, encoding: .utf8) else { return }
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?m)^\\s*\(escaped)\\s*(?::[^=\\n]+)?=\\s*([-+]?(?:\\d+\\.?\\d*|\\.\\d+)(?:[eE][-+]?\\d+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)),
              let range = Range(match.range(at: 1), in: script)
        else {
            activity = .failed(String(localized: "Parametro \(name) non trovato in model.py"))
            return
        }
        let original = script[range]
        let text = value == value.rounded() && !original.contains(".") ? String(Int(value)) : String(value)
        do {
            try script.replacingCharacters(in: range, with: text).write(to: folder.modelScript, atomically: true, encoding: .utf8)
            build(versionPrompt: "\(name) = \(text)")
        } catch {
            activity = .failed(error.localizedDescription)
        }
    }

    func compare(with number: Int?) {
        viewer.compareVersion = number
        let version = history.versions.first { $0.number == number }
        output.loadComparison(from: version.map(history.directory))
    }

    func build(versionPrompt: String? = nil) {
        guard !isBusy else { return }
        guard PythonEnvironment.shared.isReady else {
            PythonEnvironment.shared.isSetupSheetPresented = true
            return
        }
        guard hasModelScript else {
            activity = .failed(String(localized: "Nessun model.py da compilare"))
            return
        }
        activity = .working(String(localized: "Compilazione di model.py…"))
        buildError = nil
        task = Task {
            do {
                let result = try await ModelBuilder.build(folder, python: PythonEnvironment.shared.interpreter)
                buildDidFinish(result, versionPrompt: versionPrompt)
            } catch {
                buildError = error.localizedDescription
                activity = .failed(String(localized: "Errore nello script"))
            }
        }
    }

    private func buildDidFinish(_ result: ProcessResult, versionPrompt: String?) {
        output.reload()
        if result.wasInterrupted {
            activity = .failed(String(localized: "Compilazione interrotta"))
        } else if result.status == 0 {
            missingOutputs = output.missingFiles
            activity = .succeeded(String(localized: "Modello generato"))
            recordVersion(prompt: versionPrompt ?? String(localized: "Compilazione manuale di model.py"))
        } else {
            let traceback = (result.errorOutput.isEmpty ? result.output : result.errorOutput)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            buildError = traceback.split(separator: "\n").last.map(String.init) ?? String(localized: "Errore nello script")
            activity = .failed(String(localized: "Errore nello script"))
            chat.append(ChatMessage(
                role: .system,
                text: String(localized: "La compilazione di model.py non è riuscita."),
                detail: traceback,
                action: .askClaudeToFix
            ))
            chat.save()
        }
    }

    func stop() {
        task?.cancel()
    }

    func close() {
        task?.cancel()
        AppSettings.defaultLayout = layout
        watcher = nil
        save()
    }

    func save() {
        metadata.updatedAt = .now
        metadata.appVersion = Bundle.main.shortVersion
        try? ProjectStore.write(metadata, to: folder.projectFile)
    }

    func exportPackage() {
        guard let destination = ProjectPanels.chooseExportDestination(for: name) else { return }
        let files = ([folder.modelScript] + folder.expectedOutputs + [folder.animation])
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(\.path)
        try? FileManager.default.removeItem(at: destination)
        Task {
            let result = try? await ProcessRunner.run(URL(filePath: "/usr/bin/zip"), arguments: ["-j", "-q", destination.path] + files)
            if result?.status == 0 {
                activity = .succeeded(String(localized: "Pacchetto esportato"))
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } else {
                activity = .failed(String(localized: "Esportazione non riuscita"))
            }
        }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([folder.root])
    }

    func openInSlicer() {
        NSWorkspace.shared.open(folder.threeMF)
    }
}
