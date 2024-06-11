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
    private(set) var versions = ""
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
