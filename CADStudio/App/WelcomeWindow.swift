import SwiftUI

struct WelcomeWindow: View {
    static let id = "welcome"

    @Binding var isCreatingProject: Bool
    @Environment(RecentProjects.self) private var recents
    @Environment(\.openWindow) private var openWindow
    @State private var selection: URL?
    @Bindable private var python = PythonEnvironment.shared
    @State private var isShowingSetup = !AppSettings.hasCompletedSetup

    var body: some View {
        HStack(spacing: 0) {
            actions
                .frame(width: 480)
            Divider()
            recentList
                .frame(width: 300)
        }
        .frame(height: 460)
        .ignoresSafeArea()
        .sheet(isPresented: $isShowingSetup, onDismiss: { python.isSetupSheetPresented = !python.isReady }) {
            SetupSheet()
        }
        .sheet(isPresented: $python.isSetupSheetPresented) {
            PythonSetupSheet(python: python)
        }
        .sheet(isPresented: $isCreatingProject) {
            NewProjectSheet { url in openWindow(value: url) }
        }
    }

    private var actions: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)
            Text("CAD Studio")
                .font(.system(size: 36, weight: .bold))
            Text("Versione \(Bundle.main.shortVersion)")
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Spacer()
            VStack(spacing: 8) {
                WelcomeActionButton(title: "Crea nuovo progetto…", systemImage: "plus.square") {
                    isCreatingProject = true
                }
                WelcomeActionButton(title: "Apri progetto esistente…", systemImage: "folder") {
                    if let url = ProjectPanels.chooseExistingProject() {
                        openWindow(value: url)
                    }
                }
            }
            .frame(width: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var recentList: some View {
        List(recents.urls, id: \.self, selection: $selection) { url in
            RecentProjectRow(url: url)
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: URL.self) { urls in
            if let url = urls.first {
                Button("Apri") { openWindow(value: url) }
                Button("Mostra nel Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Divider()
                Button("Rimuovi dalla lista") { recents.remove(url) }
            }
        } primaryAction: { urls in
            if let url = urls.first {
                openWindow(value: url)
            }
        }
        .overlay {
            if recents.urls.isEmpty {
                Text("Nessun progetto recente")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WelcomeActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 24)
                Text(title)
                    .fontWeight(.medium)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct RecentProjectRow: View {
    let url: URL

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
                .frame(width: 40, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        let file = ProjectFolder(root: url).png
        if let image = NSImage(contentsOf: file) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: "cube")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
