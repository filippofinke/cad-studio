import SwiftUI

struct ProjectWindow: View {
    let url: URL?
    @Environment(RecentProjects.self) private var recents
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var project: Project?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let project {
                ProjectWorkspace(project: project)
            } else if let loadError {
                ContentUnavailableView {
                    Label("Impossibile aprire il progetto", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                }
                .frame(minWidth: 480, minHeight: 320)
            } else {
                ProgressView()
                    .frame(minWidth: 960, minHeight: 600)
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard project == nil else { return }
        guard let url else {
            loadError = String(localized: "Nessuna cartella di progetto indicata.")
            return
        }
        do {
            project = try Project(url: url)
            recents.add(url)
            dismissWindow(id: WelcomeWindow.id)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct ProjectWorkspace: View {
    let project: Project
    @Bindable private var python = PythonEnvironment.shared
    @Bindable private var claude = ClaudeLocator.shared

    var body: some View {
        ProjectSplitView(project: project, layout: project.displayedLayout)
            .frame(minWidth: 960, minHeight: 600)
            .toolbar { ProjectToolbar(project: project) }
            .toolbar(removing: .title)
            .navigationTitle(project.name)
            .focusedSceneValue(\.project, project)
            .onDisappear { project.close() }
            .sheet(isPresented: $python.isSetupSheetPresented) {
                PythonSetupSheet(python: python)
            }
            .sheet(isPresented: $claude.isMissingSheetPresented) {
                ClaudeMissingSheet(locator: claude)
            }
    }
}

struct ProjectSplitView: NSViewControllerRepresentable {
    let project: Project
    let layout: LayoutNode

    func makeNSViewController(context: Context) -> WorkspaceViewController {
        let project = project
        let hosts: [Pane: NSViewController] = [
            .chat: hostingController(PaneContainer(pane: .chat, project: project) { ChatView(project: project) }),
            .model3D: hostingController(PaneContainer(pane: .model3D, project: project) { ModelPane(project: project) }),
            .schematic: hostingController(PaneContainer(pane: .schematic, project: project) { SchematicPane(project: project) }),
        ]
        let controller = WorkspaceViewController(hosts: hosts) { path, fraction in
            project.setFraction(fraction, at: path)
        }
        project.paneLocator = { [weak controller] point in controller?.locate(screenPoint: point) }
        return controller
    }

    func updateNSViewController(_ controller: WorkspaceViewController, context: Context) {
        controller.show(layout)
    }
}

struct ProjectToolbar: ToolbarContent {
    let project: Project

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                project.isChatVisible.toggle()
            } label: {
                Label("Mostra o nascondi la chat", systemImage: "sidebar.left")
            }
            .help("Mostra o nascondi la chat (⌘0)")

            Button {
                project.build()
            } label: {
                Label("Compila modello", systemImage: "play.fill")
            }
            .help("Compila modello (⌘B)")
            .disabled(project.isBusy)

            Button {
                project.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .help("Interrompi (⌘.)")
            .disabled(!project.isBusy)
        }

        ToolbarItem(placement: .principal) {
            ActivityViewer(project: project)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            VersionMenu(project: project)

            Button {
                project.revealInFinder()
            } label: {
                Label("Mostra nel Finder", systemImage: "folder")
            }
            .help("Mostra nel Finder")

            Button {
                project.exportPackage()
            } label: {
                Label("Esporta pacchetto", systemImage: "square.and.arrow.up")
            }
            .help("Esporta STEP, 3MF, STL, tavola PDF e model.py in un archivio ZIP (⇧⌘E)")
            .disabled(!project.output.hasThreeMF || project.isBusy)

            Button {
                project.openInSlicer()
            } label: {
                Label("Apri in slicer", systemImage: "arrow.up.forward.app")
            }
            .help("Apri il file 3MF nello slicer predefinito")
            .disabled(!project.output.hasThreeMF)

            Button {
                project.areParametersVisible.toggle()
            } label: {
                Label("Parametri", systemImage: "slider.horizontal.3")
            }
            .help("Mostra o nascondi i parametri (⌥⌘I)")
        }
    }
}

extension FocusedValues {
    @Entry var project: Project?
}
