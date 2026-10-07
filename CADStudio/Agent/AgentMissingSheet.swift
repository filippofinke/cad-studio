import SwiftUI

struct AgentMissingSheet: View {
    @Bindable var locator: AgentLocator
    @AppStorage private var customPath: String

    init(locator: AgentLocator) {
        self.locator = locator
        _customPath = AppStorage(wrappedValue: "", locator.engine.pathKey)
    }

    private var engine: AgentEngine { locator.engine }

    private var installCommands: [String] {
        switch engine {
        case .claude: ["curl -fsSL https://claude.ai/install.sh | bash", "npm install -g @anthropic-ai/claude-code"]
        case .codex: ["npm install -g @openai/codex", "brew install --cask codex"]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("\(engine.name) non trovato")
                    .font(.headline)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
            Text("CAD Studio usa \(engine.name) installato su questo Mac. Installalo dal Terminale con uno dei comandi seguenti, poi esegui `\(engine.loginCommand)` per effettuare l’accesso.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(installCommands, id: \.self) { command in
                CodeBlock(code: command)
            }
            LabeledContent("Percorso dell’eseguibile:") {
                TextField("Percorso", text: $customPath, prompt: Text("~/.local/bin/\(engine.command)"))
                    .labelsHidden()
                    .fontDesign(.monospaced)
            }
            .font(.callout)
            if locator.state == .missing {
                Text("Nessun eseguibile funzionante trovato.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Apri il Terminale") {
                    NSWorkspace.shared.openApplication(
                        at: URL(filePath: "/System/Applications/Utilities/Terminal.app"),
                        configuration: NSWorkspace.OpenConfiguration()
                    )
                }
                Spacer()
                Button("Chiudi") {
                    locator.isMissingSheetPresented = false
                }
                .keyboardShortcut(.cancelAction)
                Button("Verifica") {
                    Task {
                        await locator.locate()
                        if locator.executable != nil {
                            locator.isMissingSheetPresented = false
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(locator.state == .checking)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
