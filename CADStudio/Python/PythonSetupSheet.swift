import SwiftUI

struct PythonSetupSheet: View {
    @Bindable var python: PythonEnvironment
    @State private var showsLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Installazione componenti")
                        .font(.headline)
                    Text("CAD Studio usa un ambiente Python dedicato con build123d, matplotlib e numpy per generare modelli e tavole tecniche. L’installazione scarica circa 200 MB.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if python.isInstalling || python.progress > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: python.progress)
                    Text(python.step)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if case .failed(let message) = python.state {
                Label(message, systemImage: "xmark.octagon.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Mostra dettagli", isExpanded: $showsLog) {
                ScrollView {
                    Text(python.log)
                        .font(.system(size: 11))
                        .fontDesign(.monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .defaultScrollAnchor(.bottom)
                .frame(height: 180)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
            .font(.callout)
            HStack {
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(width: 520)
        .interactiveDismissDisabled(python.isInstalling)
    }

    @ViewBuilder
    private var buttons: some View {
        switch python.state {
        case .ready:
            Button("Fine") {
                python.isSetupSheetPresented = false
            }
            .keyboardShortcut(.defaultAction)
        case .installing, .checking:
            Button("Installazione in corso…") {}
                .disabled(true)
        default:
            Button("Più tardi") {
                python.isSetupSheetPresented = false
            }
            .keyboardShortcut(.cancelAction)
            Button("Installa") {
                Task { await python.reinstall() }
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}
