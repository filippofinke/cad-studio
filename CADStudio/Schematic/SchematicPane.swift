import PDFKit
import SwiftUI

struct SchematicPane: View {
    let project: Project
    @FocusState private var isFocused: Bool

    private var output: ProjectOutput { project.output }
    private var viewer: SchematicViewer { project.schematic }

    private var pages: [DrawingPage] { output.drawingPages }

    private var currentPage: DrawingPage? {
        pages.isEmpty ? nil : pages[min(viewer.page, pages.count - 1)]
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            PaneStatusBar(info: output.hasSVG ? viewer.zoom.formatted(.percent.precision(.fractionLength(0))) : "") {
                controls
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onChange(of: project.focusRequest) { _, request in
            if request?.pane == .schematic {
                isFocused = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let currentPage {
            SVGWebView(file: currentPage.file, revision: "\(output.schematicRevision)-\(currentPage.file.lastPathComponent)", viewer: viewer)
                .accessibilityLabel(Text("Tavola tecnica, \(currentPage.title)"))
        } else {
            ContentUnavailableView {
                Label("Nessun modello", systemImage: "doc.text.image")
            } description: {
                Text("Descrivi un oggetto nella chat per iniziare")
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if pages.count > 1, let currentPage {
                pagePicker(currentPage)
            }
            Group {
                Button {
                    viewer.zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Riduci (⌘−)")
                .accessibilityLabel(Text("Riduci"))
                Button {
                    viewer.zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Ingrandisci (⌘+)")
                .accessibilityLabel(Text("Ingrandisci"))
                Button("Adatta") {
                    viewer.fit()
                }
            }
            .disabled(!output.hasSVG)
            Button("Apri in Anteprima") {
                openInPreview()
            }
            .disabled(previewFile == nil)
        }
        .buttonStyle(.borderless)
    }

    private func pagePicker(_ currentPage: DrawingPage) -> some View {
        let index = min(viewer.page, pages.count - 1)
        return HStack(spacing: 2) {
            Button {
                viewer.page = max(index - 1, 0)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(index == 0)
            .help("Pagina precedente")
            .accessibilityLabel(Text("Pagina precedente"))
            Menu {
                ForEach(Array(pages.enumerated()), id: \.offset) { offset, page in
                    Button("\(offset + 1). \(page.title)") {
                        viewer.page = offset
                    }
                }
            } label: {
                Text("\(index + 1)/\(pages.count) · \(currentPage.title)")
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Scegli la pagina della tavola")
            Button {
                viewer.page = min(index + 1, pages.count - 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(index == pages.count - 1)
            .help("Pagina successiva")
            .accessibilityLabel(Text("Pagina successiva"))
        }
    }

    private var previewFile: URL? {
        [project.folder.pdf, project.folder.png].first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private var previewFiles: [URL] {
        guard let file = previewFile else { return [] }
        let pagePDFs = pages.dropFirst()
            .map { $0.file.deletingPathExtension().appendingPathExtension("pdf") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard file == project.folder.pdf, !pagePDFs.isEmpty, (PDFDocument(url: file)?.pageCount ?? 0) < pages.count else {
            return [file]
        }
        return [file] + pagePDFs
    }

    private func openInPreview() {
        let files = previewFiles
        guard !files.isEmpty else { return }
        guard let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") else {
            files.forEach { NSWorkspace.shared.open($0) }
            return
        }
        NSWorkspace.shared.open(files, withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
    }
}
