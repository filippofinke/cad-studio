import SwiftUI

struct NewProjectSheet: View {
    let onCreate: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNameValid: Bool {
        !trimmedName.isEmpty
            && !trimmedName.hasPrefix(".")
            && !trimmedName.contains("/")
            && !trimmedName.contains(":")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scegli le opzioni per il nuovo progetto:")
                .font(.headline)
            LabeledContent("Nome progetto:") {
                TextField("Nome progetto", text: $name, prompt: Text("Staffa a L"))
                    .labelsHidden()
                    .onSubmit(create)
            }
            Text("Nel passaggio successivo sceglierai dove creare la cartella del progetto.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Annulla", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Avanti", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isNameValid)
            }
        }
        .padding(20)
        .frame(width: 460)
        .alert(
            "Impossibile creare il progetto",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
            presenting: errorMessage
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }

    private func create() {
        guard isNameValid, let parent = ProjectPanels.chooseParentFolder(for: trimmedName) else { return }
        do {
            let url = try ProjectStore.create(named: trimmedName, in: parent)
            dismiss()
            onCreate(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
