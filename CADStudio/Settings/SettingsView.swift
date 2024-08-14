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
