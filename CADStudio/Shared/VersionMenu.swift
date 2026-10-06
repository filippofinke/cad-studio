import SwiftUI

struct VersionMenu: View {
    let project: Project

    var body: some View {
        Menu {
            if project.history.versions.isEmpty {
                Text("Nessuna versione salvata")
            } else {
                Section(project.isBusy ? "Disponibili al termine della generazione" : "Torna a una versione") {
                    ForEach(project.history.versions.reversed()) { version in
                        Button {
                            project.restore(version)
                        } label: {
                            if project.metadata.currentVersion == version.number {
                                Label("Versione \(version.number) · \(summary(of: version.prompt))", systemImage: "checkmark")
                            } else {
                                Text("Versione \(version.number) · \(summary(of: version.prompt))")
                            }
                            Text("\(version.createdAt.formatted(.relative(presentation: .named))) · \(version.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        }
                        .disabled(project.isBusy)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                if let current = project.metadata.currentVersion {
                    Text("v\(current)")
                        .monospacedDigit()
                }
            }
            .accessibilityLabel(Text("Versioni"))
        }
        .help("Storico delle versioni")
    }

    private func summary(of prompt: String) -> String {
        let line = prompt.split(separator: "\n").first.map(String.init) ?? prompt
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }
}
