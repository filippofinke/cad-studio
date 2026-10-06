import SwiftUI

struct VersionMenu: View {
    let project: Project

    var body: some View {
        Menu {
            if project.history.versions.isEmpty {
                Text("Nessuna versione salvata")
            }
            ForEach(project.history.versions.reversed()) { version in
                Toggle(isOn: Binding(
                    get: { project.metadata.currentVersion == version.number },
                    set: { _ in project.restore(version) }
                )) {
                    Text("Versione \(version.number) · \(summary(of: version.prompt))")
                    Text("\(version.createdAt.formatted(.relative(presentation: .named))) · \(version.createdAt.formatted(date: .abbreviated, time: .shortened))")
                }
            }
        } label: {
            Label("Versioni", systemImage: "clock.arrow.circlepath")
        }
        .help("Storico delle versioni")
        .disabled(project.isBusy)
    }

    private func summary(of prompt: String) -> String {
        let line = prompt.split(separator: "\n").first.map(String.init) ?? prompt
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }
}
