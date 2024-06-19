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

    func run(_ prompt: String, images: [URL] = [], allowsResume: Bool = true, attempt: Int = 0) async {
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
            if sessionID != nil, !result.wasInterrupted, isBusySession(result) {
                closeLog()
                if attempt == 0 {
                    try? await Task.sleep(for: .seconds(5))
                    await run(prompt, images: images, allowsResume: true, attempt: 1)
                } else {
                    project.metadata.sessionID = nil
                    chat.append(ChatMessage(
                        role: .system,
                        text: String(localized: "La sessione precedente è ancora in uso da un altro processo: il contesto della conversazione è ripartito, ma il model.py esistente resta la base del lavoro.")
                    ))
                    await run(prompt, images: images, allowsResume: false)
                }
                return
            }
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
