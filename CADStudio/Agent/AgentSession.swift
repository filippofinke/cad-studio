import Foundation

@MainActor
final class AgentSession {
    private unowned let project: Project
    private var streamingID: UUID?
    private var unconfirmedTextIDs: [UUID] = []
    private var hasText = false
    private var turnResult: TurnResult?
    private var log: FileHandle?

    init(project: Project) {
        self.project = project
    }

    private var chat: ChatViewModel { project.chat }

    func run(_ prompt: String, allowsResume: Bool = true) async {
        streamingID = nil
        unconfirmedTextIDs = []
        hasText = false
        turnResult = nil

        guard let claude = await ClaudeLocator.shared.resolve() else {
            chat.append(ChatMessage(
                role: .system,
                text: String(localized: "Claude Code non è installato oppure non è stato trovato. Installalo o indica il percorso dell’eseguibile."),
                action: .configureClaude
            ))
            ClaudeLocator.shared.isMissingSheetPresented = true
            project.agentDidFinish(.failed(String(localized: "Claude Code non trovato")))
            return
        }

        let sessionID = allowsResume ? project.metadata.sessionID : nil
        let request = ClaudeRequest(
            prompt: prompt,
            sessionID: sessionID,
            projectName: project.name,
            python: PythonEnvironment.shared.interpreter
        )
        openLog()
        defer { closeLog() }

        do {
            let result = try await ClaudeRunner.run(claude, request: request, directory: project.folder.root) { [weak self] line in
                self?.handle(line)
            }
            if sessionID != nil, !result.wasInterrupted, isMissingSession(result) {
                project.metadata.sessionID = nil
                chat.append(ChatMessage(
                    role: .system,
                    text: String(localized: "La sessione precedente non è stata trovata: il contesto della conversazione è ripartito, ma il model.py esistente resta la base del lavoro.")
                ))
                closeLog()
                await run(prompt, allowsResume: false)
                return
            }
            finish(result)
        } catch {
            chat.append(ChatMessage(role: .system, text: String(localized: "Impossibile avviare Claude Code."), detail: error.localizedDescription))
            project.agentDidFinish(.failed(String(localized: "Errore di Claude Code")))
        }
    }

    private func handle(_ line: String) {
        log?.write(Data((line + "\n").utf8))
        switch StreamEvent(line: line) {
        case .started(let sessionID):
            if project.metadata.sessionID != sessionID {
                project.metadata.sessionID = sessionID
            }
            project.save()
        case .blockStarted:
            streamingID = nil
        case .textDelta(let text):
            appendStreamingText(text)
            show(.working(String(localized: "Claude sta scrivendo…")))
        case .thinking:
            show(.working(String(localized: "Claude sta ragionando…")))
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
            chat.append(ChatMessage(
                role: .tool,
                text: title,
                tool: ToolActivity(toolUseID: id, name: name, input: ToolSummary.inputText(name: name, input: input))
            ))
            project.activity = .working(String(localized: "Claude sta lavorando… · \(title)"))
        }
    }

    private func finish(_ result: ProcessResult) {
        chat.failRunningTools()
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
                text: String(localized: "Claude Code non è autenticato. Apri il Terminale ed esegui `claude` una volta per effettuare l’accesso."),
                detail: details,
                action: .openTerminal
            ))
            project.agentDidFinish(.failed(String(localized: "Accesso a Claude Code richiesto")))
        } else {
            chat.append(ChatMessage(
                role: .system,
                text: String(localized: "Claude Code ha terminato con un errore (codice \(result.status))."),
                detail: details.isEmpty ? nil : details
            ))
            project.agentDidFinish(.failed(String(localized: "Errore di Claude Code")))
        }
    }

    private func isMissingSession(_ result: ProcessResult) -> Bool {
        guard turnResult == nil || turnResult?.isError == true else { return false }
        let text = (turnResult?.text ?? "") + result.output + result.errorOutput
        return text.localizedCaseInsensitiveContains("No conversation found")
    }

    private func isAuthenticationError(_ text: String) -> Bool {
        ["invalid api key", "/login", "not logged in", "authentication", "oauth token", "unauthorized"]
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
