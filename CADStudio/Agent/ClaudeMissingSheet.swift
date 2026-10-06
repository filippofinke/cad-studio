import SwiftUI

struct ClaudeMissingSheet: View {
    @Bindable var locator: ClaudeLocator
    @AppStorage(AppSettings.claudePathKey) private var customPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("Claude Code non trovato")
                    .font(.headline)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
            Text("CAD Studio usa Claude Code installato su questo Mac. Installalo dal Terminale con uno dei comandi seguenti, poi esegui `claude` una volta per effettuare l’accesso.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            CodeBlock(code: "curl -fsSL https://claude.ai/install.sh | bash")
            CodeBlock(code: "npm install -g @anthropic-ai/claude-code")
            LabeledContent("Percorso dell’eseguibile:") {
                TextField("Percorso", text: $customPath, prompt: Text("~/.local/bin/claude"))
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
