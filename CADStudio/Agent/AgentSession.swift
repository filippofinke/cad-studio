import Foundation

@MainActor
final class AgentSession {
    private unowned let project: Project
    private var streamingID: UUID?
    private var unconfirmedTextIDs: [UUID] = []
    private var hasText = false
    private var turnResult: TurnResult?
    private var liveTools: [Int: LiveTool] = [:]
    private var thinkingIndex: Int?
    private var thinkingStart = Date.now

    private struct LiveTool {
        let id: String
        let name: String
        var json = ""
        var updatedAt = Date.distantPast
    }
    private var log: FileHandle?
    private var engine = AgentEngine.current
    private var translator = CodexTranslator()

    init(project: Project) {
        self.project = project
    }

    private var chat: ChatViewModel { project.chat }

    func run(_ prompt: String, images: [URL] = [], allowsResume: Bool = true) async {
        engine = AgentEngine.current
        translator = CodexTranslator()
        streamingID = nil
        unconfirmedTextIDs = []
        hasText = false
        turnResult = nil
        liveTools = [:]
        thinkingIndex = nil

        let locator = AgentLocator.current
        guard let executable = await locator.resolve() else {
            chat.append(ChatMessage(
                role: .system,
                text: String(localized: "\(engine.name) non è installato oppure non è stato trovato. Installalo o indica il percorso dell’eseguibile."),
                action: .configureClaude
            ))
            locator.isMissingSheetPresented = true
            project.agentDidFinish(.failed(String(localized: "\(engine.name) non trovato")))
            return
        }

        let sessionID = allowsResume ? project.metadata.sessionID : nil
        let request = ClaudeRequest(
            prompt: prompt,
            sessionID: sessionID,
            projectName: project.name,
            python: PythonEnvironment.shared.interpreter,
            environment: environmentSummary(),
            images: images
        )
        openLog()
        defer { closeLog() }

        do {
            let directory = project.folder.root
            let onLine: ProcessRunner.LineHandler = { [weak self] line in
                self?.handle(line)
            }
            let result = engine == .codex
                ? try await CodexRunner.run(executable, request: request, directory: directory, onLine: onLine)
                : try await ClaudeRunner.run(executable, request: request, directory: directory, onLine: onLine)
            if sessionID != nil, !result.wasInterrupted, isMissingSession(result) {
                project.metadata.sessionID = nil
                chat.append(ChatMessage(
                    role: .system,
                    text: String(localized: "La sessione precedente non è stata trovata: il contesto della conversazione è ripartito, ma il model.py esistente resta la base del lavoro.")
                ))
                closeLog()
                await run(prompt, images: images, allowsResume: false)
                return
            }
            finish(result)
        } catch {
            chat.append(ChatMessage(role: .system, text: String(localized: "Impossibile avviare \(engine.name)."), detail: error.localizedDescription))
            project.agentDidFinish(.failed(String(localized: "Errore di \(engine.name)")))
        }
    }

    private func handle(_ line: String) {
        log?.write(Data((line + "\n").utf8))
        let events = engine == .codex ? translator.events(for: line) : [StreamEvent(line: line)]
        events.forEach(process)
    }

    private func process(_ event: StreamEvent) {
        switch event {
        case .started(let sessionID):
            if project.metadata.sessionID != sessionID {
                project.metadata.sessionID = sessionID
            }
            project.save()
        case .blockStarted(let index, let kind):
            streamingID = nil
            startBlock(index, kind: kind)
        case .blockStopped(let index):
            stopBlock(index)
        case .textDelta(let text):
            appendStreamingText(text)
            show(.working(String(localized: "\(engine.name) sta scrivendo…")))
        case .toolInputDelta(let index, let json):
            appendToolInput(json, to: index)
        case .thinking:
            show(.working(String(localized: "\(engine.name) sta ragionando…")))
        case .thinkingTokens(let tokens):
            updateThinking(tokens: tokens)
        case .assistant(let blocks):
            blocks.forEach(handle)
        case .toolResults(let results):
            for result in results {
                chat.completeTool(result.toolUseID, output: result.content, failed: result.isError)
            }
        case .finished(let result):
            turnResult = result
            if let sessionID = result.sessionID {
                project.metadata.sessionID = sessionID
            }
        case .unknown:
            break
        }
    }

    private func startBlock(_ index: Int, kind: BlockKind) {
        switch kind {
        case .thinking:
            thinkingIndex = index
            thinkingStart = .now
            chat.activeThinkingID = chat.append(ChatMessage(role: .thinking, text: String(localized: "\(engine.name) sta ragionando…")))
            show(.working(String(localized: "\(engine.name) sta ragionando…")))
        case .toolUse(let id, let name):
            liveTools[index] = LiveTool(id: id, name: name)
            let title = liveTitle(name: name, json: "")
            chat.append(ChatMessage(role: .tool, text: title, tool: ToolActivity(toolUseID: id, name: name, input: "")))
            show(.working(String(localized: "\(engine.name) sta lavorando… · \(title)")))
        case .text, .other:
            break
        }
    }

    private func stopBlock(_ index: Int) {
        if index == thinkingIndex, let id = chat.activeThinkingID {
            let seconds = max(1, Int(Date.now.timeIntervalSince(thinkingStart).rounded()))
            chat.setText(String(localized: "Ha ragionato per \(seconds) s"), of: id)
            chat.activeThinkingID = nil
            thinkingIndex = nil
        }
        if let tool = liveTools.removeValue(forKey: index), chat.tool(tool.id)?.state == .running {
            chat.updateTool(tool.id, title: liveTitle(name: tool.name, json: tool.json), preview: nil)
        }
    }

    private func appendToolInput(_ json: String, to index: Int) {
        guard var tool = liveTools[index] else { return }
        tool.json += json
        if Date.now.timeIntervalSince(tool.updatedAt) > 0.15 {
            tool.updatedAt = .now
            let title = liveTitle(name: tool.name, json: tool.json)
            chat.updateTool(tool.id, title: title, preview: ToolSummary.livePreview(name: tool.name, json: tool.json))
            show(.working(String(localized: "\(engine.name) sta lavorando… · \(title)")))
        }
        liveTools[index] = tool
    }

    private func updateThinking(tokens: Int) {
        guard let id = chat.activeThinkingID else { return }
        chat.setText(String(localized: "Sta ragionando · circa \(tokens.formatted()) token"), of: id)
    }

    private func liveTitle(name: String, json: String) -> String {
        ToolSummary.liveTitle(name: name, json: json, root: project.folder.root, python: PythonEnvironment.shared.interpreter)
    }

    private func environmentSummary() -> String {
        let folder = project.folder
        let manager = FileManager.default
        func names(in directory: URL) -> String {
            let files = ((try? manager.contentsOfDirectory(atPath: directory.path)) ?? [])
                .filter { !$0.hasPrefix(".") }
                .sorted()
            return files.isEmpty ? "empty" : files.joined(separator: ", ")
        }
        var lines = ["- Python packages: \(PythonEnvironment.shared.versions.isEmpty ? "build123d, matplotlib, numpy" : PythonEnvironment.shared.versions)"]
        if let script = try? String(contentsOf: folder.modelScript, encoding: .utf8) {
            lines.append("- model.py exists (\(script.split(separator: "\n", omittingEmptySubsequences: false).count) lines)")
        } else {
            lines.append("- model.py does not exist yet: create it")
        }
        lines.append("- output/: \(names(in: folder.output))")
        if manager.fileExists(atPath: folder.references.path) {
            lines.append("- references/: \(names(in: folder.references))")
        }
        return lines.joined(separator: "\n")
    }

    private func show(_ activity: Activity) {
        if project.activity != activity {
            project.activity = activity
        }
    }

    private func appendStreamingText(_ text: String) {
        let id: UUID
        if let streamingID {
            id = streamingID
        } else {
            id = chat.append(ChatMessage(role: .assistant, text: ""))
            streamingID = id
            unconfirmedTextIDs.append(id)
        }
        chat.appendText(text, to: id)
    }

    private func handle(_ block: AssistantBlock) {
        switch block {
        case .text(let text):
            hasText = true
            if unconfirmedTextIDs.isEmpty {
                chat.append(ChatMessage(role: .assistant, text: text))
            } else {
                chat.setText(text, of: unconfirmedTextIDs.removeFirst())
            }
        case .toolUse(let id, let name, let input):
            streamingID = nil
            let title = ToolSummary.title(
                name: name,
                input: input,
                root: project.folder.root,
                python: PythonEnvironment.shared.interpreter
            )
            let inputText = ToolSummary.inputText(name: name, input: input)
            if chat.containsTool(id) {
                chat.updateTool(id, title: title, input: inputText, preview: nil)
            } else {
                chat.append(ChatMessage(role: .tool, text: title, tool: ToolActivity(toolUseID: id, name: name, input: inputText)))
            }
            show(.working(String(localized: "\(engine.name) sta lavorando… · \(title)")))
        }
    }

    private func finish(_ result: ProcessResult) {
        chat.failRunningTools()
        chat.activeThinkingID = nil
        if result.wasInterrupted {
            chat.append(ChatMessage(role: .summary, text: String(localized: "Interrotto")))
            project.agentDidFinish(.failed(String(localized: "Interrotto")))
            return
        }
        guard let turnResult, !turnResult.isError else {
            reportFailure(turnResult?.text ?? "", result: result)
            return
        }
        if !hasText, !turnResult.text.isEmpty {
            chat.append(ChatMessage(role: .assistant, text: turnResult.text))
        }
        project.agentDidFinish(nil)
    }

    private func reportFailure(_ message: String, result: ProcessResult) {
        let details = [message, result.errorOutput, result.status == 0 ? "" : result.output]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if isAuthenticationError(details) {
            chat.append(ChatMessage(
                role: .system,
                text: String(localized: "\(engine.name) non è autenticato. Apri il Terminale ed esegui `\(engine.loginCommand)` per effettuare l’accesso."),
                detail: details,
                action: .openTerminal
            ))
            project.agentDidFinish(.failed(String(localized: "Accesso a \(engine.name) richiesto")))
        } else {
            chat.append(ChatMessage(
                role: .system,
                text: String(localized: "\(engine.name) ha terminato con un errore (codice \(result.status))."),
                detail: details.isEmpty ? nil : details
            ))
            project.agentDidFinish(.failed(String(localized: "Errore di \(engine.name)")))
        }
    }

    private func isMissingSession(_ result: ProcessResult) -> Bool {
        guard turnResult == nil || turnResult?.isError == true else { return false }
        let text = (turnResult?.text ?? "") + result.output + result.errorOutput
        return text.localizedCaseInsensitiveContains("No conversation found")
            || text.localizedCaseInsensitiveContains("no rollout found")
            || text.localizedCaseInsensitiveContains("session not found")
            || text.localizedCaseInsensitiveContains("thread not found")
    }

    private func isAuthenticationError(_ text: String) -> Bool {
        ["invalid api key", "/login", "not logged in", "authentication", "oauth token", "unauthorized", "codex login", "401"]
            .contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func openLog() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        let url = project.folder.logs.appending(path: "\(formatter.string(from: .now)).jsonl")
        try? FileManager.default.createDirectory(at: project.folder.logs, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        log = try? FileHandle(forWritingTo: url)
    }

    private func closeLog() {
        try? log?.close()
        log = nil
    }
}
