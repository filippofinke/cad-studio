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
