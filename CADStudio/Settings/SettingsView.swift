import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Generale", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Agente", systemImage: "sparkles") {
                AgentSettingsView()
            }
            Tab("Python", systemImage: "chevron.left.forwardslash.chevron.right") {
                PythonSettingsView(python: PythonEnvironment.shared)
            }
            Tab("Avanzate", systemImage: "gearshape.2") {
                AdvancedSettingsView()
            }
        }
        .frame(width: 600)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(AppSettings.defaultProjectLocationKey) private var defaultLocation = ""
    @State private var language = UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first
        .flatMap { code in AppLanguage.allCases.first { code.hasPrefix($0.rawValue) } } ?? .system

    var body: some View {
        Form {
            LabeledContent("Posizione dei nuovi progetti:") {
                HStack {
                    PathText(url: AppSettings.defaultProjectLocation)
                    Button("Scegli…") {
                        if let url = ProjectPanels.chooseFolder(startingAt: AppSettings.defaultProjectLocation) {
                            defaultLocation = url.path
                        }
                    }
                }
            }
            Section {
                Picker("Lingua:", selection: $language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.title).tag(language)
                    }
                }
                .onChange(of: language) {
                    if language == .system {
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
                    }
                }
            } footer: {
                Text("La nuova lingua viene applicata al prossimo avvio di CAD Studio.")
                    .foregroundStyle(.secondary)
            }
            PrintPreferencesSection()
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AgentSettingsView: View {
    @AppStorage(AppSettings.agentEngineKey) private var engineName = AgentEngine.claude.rawValue
    @AppStorage(AppSettings.claudeEffortKey) private var effort = ""
    @AppStorage(AppSettings.restrictedBashKey) private var restrictedBash = false

    private var engine: AgentEngine { AgentEngine(rawValue: engineName) ?? .claude }

    var body: some View {
        Form {
            Section {
                Picker("Agente:", selection: $engineName) {
                    ForEach(AgentEngine.allCases, id: \.self) { engine in
                        Text(engine.name).tag(engine.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("CAD Studio usa l’agente installato su questo Mac e il tuo piano. Puoi cambiarlo in qualsiasi momento: i progetti esistenti continuano con l’agente scelto qui.")
                    .foregroundStyle(.secondary)
            }
            AgentEngineSection(locator: AgentLocator.locator(for: engine))
                .id(engine)
            Section {
                Picker("Effort:", selection: $effort) {
                    Text("Predefinito dell’agente").tag("")
                    Text("Basso, più veloce").tag("low")
                    Text("Medio").tag("medium")
                    Text("Alto, più accurato").tag("high")
                }
            } footer: {
                Text("Un effort più basso fa ragionare meno l’agente prima di agire: le risposte arrivano prima, ma per pezzi complessi potrebbero servire più correzioni.")
                    .foregroundStyle(.secondary)
            }
            if engine == .claude {
                Section {
                    Toggle("Bash limitato", isOn: $restrictedBash)
                } footer: {
                    Text("Con Bash limitato l’agente può eseguire solo l’interprete Python dell’ambiente di CAD Studio e alcuni comandi di sola lettura (ls, cat, head…). È più sicuro, ma l’agente ha meno autonomia per diagnosticare i problemi e alcuni tentativi potrebbero essere rifiutati.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text("Codex lavora nella sua sandbox: può scrivere solo nella cartella del progetto e non usa la rete.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AgentEngineSection: View {
    let locator: AgentLocator
    @AppStorage private var customPath: String
    @AppStorage private var model: String

    init(locator: AgentLocator) {
        self.locator = locator
        _customPath = AppStorage(wrappedValue: "", locator.engine.pathKey)
        _model = AppStorage(wrappedValue: "", locator.engine.modelKey)
    }

    var body: some View {
        Section {
            LabeledContent("Eseguibile:") {
                switch locator.state {
                case .found(let url, _):
                    PathText(url: url)
                case .checking:
                    ProgressView()
                        .controlSize(.small)
                case .unknown:
                    Text("—")
                case .missing:
                    Text("Non trovato")
                        .foregroundStyle(.red)
                }
            }
            LabeledContent("Versione:") {
                if case .found(_, let version) = locator.state {
                    Text(version)
                        .fontDesign(.monospaced)
                        .textSelection(.enabled)
                } else {
                    Text("—")
                }
            }
            TextField("Percorso personalizzato:", text: $customPath, prompt: Text("Automatico"))
                .fontDesign(.monospaced)
            TextField("Modello:", text: $model, prompt: Text("Predefinito di \(locator.engine.name)"))
                .fontDesign(.monospaced)
            HStack {
                Spacer()
                Button("Verifica") {
                    Task { await locator.locate() }
                }
            }
        }
        .task {
            if locator.state == .unknown {
                await locator.locate()
            }
        }
    }
}

private struct PythonSettingsView: View {
    let python: PythonEnvironment

    var body: some View {
        Form {
            Section {
                LabeledContent("Interprete:") {
                    PathText(url: python.interpreter)
                }
                LabeledContent("build123d:") {
                    switch python.state {
                    case .ready(let version):
                        Text(version)
                            .fontDesign(.monospaced)
                    case .checking, .installing, .unknown:
                        ProgressView()
                            .controlSize(.small)
                    case .missing:
                        Text("Non installato")
                            .foregroundStyle(.secondary)
                    case .failed:
                        Text("Non funzionante")
                            .foregroundStyle(.red)
                    }
                }
                HStack {
                    Spacer()
                    Button("Verifica") {
                        Task { await python.check() }
                    }
                    Button("Reinstalla…") {
                        python.isSetupSheetPresented = true
                        Task { await python.reinstall() }
                    }
                }
                .disabled(python.isInstalling)
            } footer: {
                Text("Pacchetti: build123d, matplotlib, numpy.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AdvancedSettingsView: View {
    @AppStorage(AppSettings.streamingOutputKey) private var streamingOutput = true
    @AppStorage(AppSettings.isolatesClaudeKey) private var isolatesClaude = true

    var body: some View {
        Form {
            Section {
                Picker("Formato di output:", selection: $streamingOutput) {
                    Text("stream-json (in tempo reale)").tag(true)
                    Text("json (risposta unica)").tag(false)
                }
            } footer: {
                Text("Vale per Claude Code. Il formato json non mostra il testo in streaming né le singole attività, ma può essere utile con versioni che non supportano lo streaming.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Ignora le configurazioni personali dell’agente", isOn: $isolatesClaude)
            } footer: {
                Text("L’agente CAD non carica le tue impostazioni utente (hook, plugin e server MCP di Claude Code, config.toml di Codex), così parte più velocemente e risponde in modo prevedibile. Disattiva se la tua autenticazione dipende da impostazioni utente, ad esempio apiKeyHelper.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PathText: View {
    let url: URL

    var body: some View {
        Text((url.path as NSString).abbreviatingWithTildeInPath)
            .fontDesign(.monospaced)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .help(url.path)
    }
}

private enum AppLanguage: String, CaseIterable {
    case system
    case italian = "it"
    case english = "en"
    case german = "de"
    case french = "fr"

    var title: LocalizedStringKey {
        switch self {
        case .system: "Lingua di sistema"
        case .italian: "Italiano"
        case .english: "English"
        case .german: "Deutsch"
        case .french: "Français"
        }
    }
}
