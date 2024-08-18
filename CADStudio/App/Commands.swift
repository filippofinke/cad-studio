import SwiftUI

struct AppCommands: Commands {
    let recents: RecentProjects
    @Binding var isCreatingProject: Bool
    @FocusedValue(\.project) private var project
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Informazioni su CAD Studio") {
                showAboutPanel()
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("Nuovo progetto…") {
                isCreatingProject = true
                openWindow(id: WelcomeWindow.id)
            }
            .keyboardShortcut("n")

            Button("Apri progetto…") {
                if let url = ProjectPanels.chooseExistingProject() {
                    openWindow(value: url)
                }
            }
            .keyboardShortcut("o")

            Menu("Apri recenti") {
                ForEach(recents.urls, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        openWindow(value: url)
                    }
                }
                Divider()
                Button("Cancella menu") {
                    recents.clear()
                }
                .disabled(recents.urls.isEmpty)
            }

            Divider()

            Button("Finestra di benvenuto") {
                openWindow(id: WelcomeWindow.id)
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
        }

        CommandGroup(before: .toolbar) {
            Button(project?.isChatVisible == false ? "Mostra chat" : "Nascondi chat") {
                project?.isChatVisible.toggle()
            }
            .keyboardShortcut("0")
            .disabled(project == nil)

            Divider()

            Button("Vai alla chat") { project?.focus(.chat) }
                .keyboardShortcut("1")
                .disabled(project == nil)
            Button("Vai al viewer 3D") { project?.focus(.model3D) }
                .keyboardShortcut("2")
                .disabled(project == nil)
            Button("Vai alla schematica 2D") { project?.focus(.schematic) }
                .keyboardShortcut("3")
                .disabled(project == nil)
            Button(project?.areParametersVisible == true ? "Nascondi parametri" : "Mostra parametri") {
                project?.areParametersVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(project == nil)
            Button("Scrivi un messaggio") { project?.focus(.chat) }
                .keyboardShortcut("l")
                .disabled(project == nil)

            Menu("Layout") {
                Button("Chat a sinistra") { project?.setLayout(.chatLeading) }
                Button("Chat a destra") { project?.setLayout(.chatTrailing) }
                Button("Chat in basso") { project?.setLayout(.chatBottom) }
                Button("Tre colonne") { project?.setLayout(.threeColumns) }
            }
            .disabled(project == nil)

            Divider()

            Menu("Viewer 3D") {
                Button("Vista isometrica") { project?.viewer.show(.iso) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Vista frontale") { project?.viewer.show(.front) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Vista dall’alto") { project?.viewer.show(.top) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("Vista da destra") { project?.viewer.show(.right) }
                    .keyboardShortcut("4", modifiers: [.command, .option])
                Divider()
                Button("Adatta alla vista") { project?.viewer.fitToView() }
                    .keyboardShortcut("0", modifiers: [.command, .option])
            }
            .disabled(project?.output.mesh == nil)

            Menu("Schematica 2D") {
                Button("Ingrandisci") { project?.schematic.zoomIn() }
                    .keyboardShortcut("+")
                Button("Riduci") { project?.schematic.zoomOut() }
                    .keyboardShortcut("-")
                Button("Adatta alla finestra") { project?.schematic.fit() }
            }
            .disabled(project?.output.hasSVG != true)

            Divider()
        }

        CommandMenu("Modello") {
            Button("Compila modello") {
                project?.build()
            }
            .keyboardShortcut("b")
            .disabled(project == nil || project?.isBusy == true)

            Button("Stop") {
                project?.stop()
            }
            .keyboardShortcut(".")
            .disabled(project?.isBusy != true)

            Divider()

            Button("Esporta pacchetto…") { project?.exportPackage() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(project?.output.hasThreeMF != true)
            Button("Mostra nel Finder") { project?.revealInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(project == nil)
            Button("Apri in slicer") { project?.openInSlicer() }
                .disabled(project?.output.hasThreeMF != true)
        }
    }

    private func showAboutPanel() {
        let credits = String(localized: "Software open source rilasciato con licenza MIT.\nSviluppato da Filippo Finke.")
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: credits, attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: style,
            ]),
        ])
    }
}
