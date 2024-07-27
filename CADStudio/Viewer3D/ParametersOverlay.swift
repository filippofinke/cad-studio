import SwiftUI

struct ParametersOverlay: View {
    let project: Project
    @AppStorage("parametersCollapsed") private var isCollapsed = false

    private var comparison: [String: Double] {
        project.viewer.compareVersion == nil ? [:] : project.output.comparisonManifest?.parameters ?? [:]
    }

    var body: some View {
        if isCollapsed {
            Button {
                withAnimation(.snappy) { isCollapsed = false }
            } label: {
                Label("Parametri", systemImage: "slider.horizontal.3")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.separator))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .help("Espandi i parametri")
        } else {
            panel
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    withAnimation(.snappy) { isCollapsed = true }
                } label: {
                    HStack(spacing: 6) {
                        Label("Parametri", systemImage: "slider.horizontal.3")
                            .font(.headline)
                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Comprimi i parametri")
                Spacer()
                Button {
                    project.areParametersVisible = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Nascondi parametri (⌥⌘I)")
                .accessibilityLabel(Text("Nascondi parametri"))
            }
            .padding([.horizontal, .top], 12)
            .padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(project.parameters) { parameter in
                        ParameterSlider(
                            parameter: parameter,
                            previousValue: comparison[parameter.name],
                            isDisabled: project.isBusy
                        ) { value in
                            project.setParameter(parameter.name, to: value)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text("Confronta con")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Confronta con", selection: Binding(
                    get: { project.viewer.compareVersion },
                    set: { project.compare(with: $0) }
                )) {
                    Text("Nessuna").tag(Int?.none)
                    ForEach(project.history.versions.reversed()) { version in
                        Text("Versione \(version.number)").tag(Int?.some(version.number))
                    }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(project.history.versions.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, project.viewer.compareVersion == nil ? 8 : 4)
            if project.viewer.compareVersion != nil {
                Text("In arancione la forma della versione scelta. Per vederne i colori, ripristinala dal menu Versioni.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding([.horizontal, .bottom], 12)
            }
        }
        .controlSize(.small)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}
