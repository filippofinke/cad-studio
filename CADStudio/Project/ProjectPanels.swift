import AppKit

@MainActor
enum ProjectPanels {
    static func chooseExistingProject() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.message = String(localized: "Scegli la cartella del progetto da aprire")
        panel.prompt = String(localized: "Apri")
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseParentFolder(for name: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = AppSettings.defaultProjectLocation
        panel.message = String(localized: "Scegli dove creare la cartella “\(name)”")
        panel.prompt = String(localized: "Crea")
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseExportDestination(for name: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "\(name).zip"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.prompt = String(localized: "Esporta")
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFolder(startingAt directory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = directory
        panel.prompt = String(localized: "Scegli")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
