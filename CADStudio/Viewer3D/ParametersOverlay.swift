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
            .padding(.vertical, 8)
        }
        .controlSize(.small)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}

private struct ParameterSlider: View {
    let parameter: ModelParameter
    let previousValue: Double?
    let isDisabled: Bool
    let onCommit: (Double) -> Void
    @State private var value: Double
    @State private var range: ClosedRange<Double>
    @State private var isEditing = false

    init(parameter: ModelParameter, previousValue: Double?, isDisabled: Bool, onCommit: @escaping (Double) -> Void) {
        self.parameter = parameter
        self.previousValue = previousValue
        self.isDisabled = isDisabled
        self.onCommit = onCommit
        _value = State(initialValue: parameter.value)
        _range = State(initialValue: Self.range(around: parameter.value))
    }

    private var isInteger: Bool {
        parameter.value == parameter.value.rounded() && abs(parameter.value) >= 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(parameter.name)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(parameter.name)
                Spacer(minLength: 6)
                if let previousValue, previousValue != parameter.value {
                    Text(previousValue.formatted(.number.precision(.fractionLength(0...2))))
                        .font(.caption2)
                        .strikethrough()
                        .foregroundStyle(.orange)
                        .help("Valore nella versione a confronto")
                }
                TextField(parameter.name, value: $value, format: .number.precision(.fractionLength(0...3)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .labelsHidden()
                    .onSubmit(commit)
            }
            Slider(value: $value, in: range) { editing in
                isEditing = editing
                if !editing {
                    commit()
                }
            }
            .labelsHidden()
            .accessibilityLabel(Text(parameter.name))
        }
        .disabled(isDisabled)
        .onChange(of: parameter.value) {
            guard !isEditing else { return }
            value = parameter.value
            if !range.contains(parameter.value) {
                range = Self.range(around: parameter.value)
            }
        }
    }

    private func commit() {
        let rounded = isInteger ? value.rounded() : (value * 1000).rounded() / 1000
        guard rounded != parameter.value else { return }
        if !range.contains(rounded) {
            range = Self.range(around: rounded)
        }
        onCommit(rounded)
    }

    private static func range(around value: Double) -> ClosedRange<Double> {
        if value > 0 {
            return 0...max(value * 2, 1)
        }
        if value < 0 {
            return value * 2...max(-value * 2, 1)
        }
        return -10...10
    }
}
