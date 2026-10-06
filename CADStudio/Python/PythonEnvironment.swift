import Foundation

@MainActor
@Observable
final class PythonEnvironment {
    enum State: Equatable {
        case unknown
        case checking
        case ready(build123dVersion: String)
        case missing
        case installing
        case failed(String)
    }

    static let shared = PythonEnvironment()
    static let packages = ["build123d", "matplotlib", "numpy"]

    let directory = URL.applicationSupportDirectory.appending(path: "CAD Studio/venv", directoryHint: .isDirectory)
    var state = State.unknown
    var isSetupSheetPresented = false
    private(set) var log = ""
    private(set) var progress = 0.0
    private(set) var step = ""

    var interpreter: URL { directory.appending(path: "bin/python") }

    var isReady: Bool {
        if case .ready = state { true } else { false }
    }

    var isInstalling: Bool { state == .installing }

    func check() async {
        state = .checking
        guard FileManager.default.isExecutableFile(atPath: interpreter.path) else {
            state = .missing
            isSetupSheetPresented = AppSettings.hasCompletedSetup
            return
        }
        if let version = await build123dVersion() {
            state = .ready(build123dVersion: version)
        } else {
            state = .failed(String(localized: "L’ambiente Python esiste ma build123d o matplotlib non si importano."))
            isSetupSheetPresented = AppSettings.hasCompletedSetup
        }
    }

    func reinstall() async {
        try? FileManager.default.removeItem(at: directory)
        await install()
    }

    func install() async {
        guard !isInstalling else { return }
        state = .installing
        log = ""
        progress = 0
        do {
            let environment = await ShellEnvironment.shared.environment()
            try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let uv = await ShellEnvironment.shared.locate("uv") {
                try await createWithUV(uv, environment: environment)
            } else {
                try await createWithVenv(environment: environment)
            }
            advance(to: 0.95, step: String(localized: "Verifica dell’installazione…"))
            guard let version = await build123dVersion() else {
                throw PythonSetupError.verificationFailed
            }
            advance(to: 1, step: String(localized: "Componenti installati"))
            state = .ready(build123dVersion: version)
        } catch {
            appendLog(error.localizedDescription)
            step = String(localized: "Installazione non riuscita")
            state = .failed(error.localizedDescription)
        }
    }

    private func createWithUV(_ uv: URL, environment: [String: String]) async throws {
        advance(to: 0.1, step: String(localized: "Creazione dell’ambiente virtuale con uv…"))
        try await runStep(uv, ["venv", "--python", "3.12", directory.path], environment: environment)
        advance(to: 0.25, step: String(localized: "Installazione di build123d, matplotlib e numpy…"))
        try await runStep(uv, ["pip", "install", "--python", interpreter.path] + Self.packages, environment: environment)
    }

    private func createWithVenv(environment: [String: String]) async throws {
        advance(to: 0.05, step: String(localized: "Ricerca di Python 3.10–3.13…"))
        guard let python = await compatiblePython() else {
            throw PythonSetupError.pythonNotFound
        }
        advance(to: 0.1, step: String(localized: "Creazione dell’ambiente virtuale…"))
        try await runStep(python, ["-m", "venv", directory.path], environment: environment)
        advance(to: 0.2, step: String(localized: "Aggiornamento di pip…"))
        try await runStep(interpreter, ["-m", "pip", "install", "--upgrade", "pip"], environment: environment)
        advance(to: 0.25, step: String(localized: "Installazione di build123d, matplotlib e numpy…"))
        try await runStep(interpreter, ["-m", "pip", "install"] + Self.packages, environment: environment)
    }

    private func compatiblePython() async -> URL? {
        for name in ["python3.13", "python3.12", "python3.11", "python3.10", "python3"] {
            guard let candidate = await ShellEnvironment.shared.locate(name),
                  let result = try? await ProcessRunner.run(candidate, arguments: ["--version"]),
                  result.status == 0
            else { continue }
            let version = (result.output + result.errorOutput).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = version.replacingOccurrences(of: "Python ", with: "").split(separator: ".")
            if parts.count >= 2, parts[0] == "3", let minor = Int(parts[1]), (10...13).contains(minor) {
                appendLog(String(localized: "Trovato \(version) in \(candidate.path)"))
                return candidate
            }
        }
        return nil
    }

    private func runStep(_ executable: URL, _ arguments: [String], environment: [String: String]) async throws {
        appendLog("$ \(([executable.path] + arguments).joined(separator: " "))")
        let handler: ProcessRunner.LineHandler = { [weak self] line in
            self?.appendLog(line)
            self?.nudgeProgress()
        }
        let result = try await ProcessRunner.run(
            executable,
            arguments: arguments,
            environment: environment,
            onOutput: handler,
            onError: handler
        )
        guard result.status == 0 else {
            throw PythonSetupError.commandFailed(executable.lastPathComponent)
        }
    }

    private func build123dVersion() async -> String? {
        let script = "import build123d, matplotlib; print(build123d.__version__)"
        guard let result = try? await ProcessRunner.run(interpreter, arguments: ["-c", script]), result.status == 0 else {
            return nil
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func advance(to value: Double, step: String) {
        progress = value
        self.step = step
        appendLog(step)
    }

    private func nudgeProgress() {
        if progress >= 0.25, progress < 0.9 {
            progress += 0.004
        }
    }

    private func appendLog(_ line: String) {
        log += line + "\n"
    }
}

enum PythonSetupError: LocalizedError {
    case pythonNotFound
    case commandFailed(String)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            String(localized: "Non è stato trovato né uv né un Python 3.10–3.13. Installa uv (brew install uv) oppure Python 3.12 e riprova.")
        case .commandFailed(let command):
            String(localized: "Il comando “\(command)” non è riuscito. Controlla il log per i dettagli.")
        case .verificationFailed:
            String(localized: "build123d e matplotlib non si importano correttamente nell’ambiente creato.")
        }
    }
}
