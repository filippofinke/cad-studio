import SwiftUI

@main
struct CADStudioApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var recents = RecentProjects()
    @State private var isCreatingProject = false

    var body: some Scene {
        Window("Benvenuto in CAD Studio", id: WelcomeWindow.id) {
            WelcomeWindow(isCreatingProject: $isCreatingProject)
                .environment(recents)
                .windowMinimizeBehavior(.disabled)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultPosition(.center)
        .commandsRemoved()

        WindowGroup(for: URL.self) { $url in
            ProjectWindow(url: url)
                .environment(recents)
        }
        .defaultSize(width: 1320, height: 840)
        .windowToolbarStyle(.unified)
        .commands {
            AppCommands(recents: recents, isCreatingProject: $isCreatingProject)
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        RunningProcesses.shared.reapOrphans()
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            RunningProcesses.shared.terminateAll()
            exit(0)
        }
        source.resume()
        terminationSource = source
        Task {
            await PythonEnvironment.shared.check()
            await AgentLocator.current.locate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        RunningProcesses.shared.terminateAll()
    }
}
