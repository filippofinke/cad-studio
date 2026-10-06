import SwiftUI

struct PartsOverlay: View {
    let project: Project
    @AppStorage("partsCollapsed") private var isCollapsed = false

    private var viewer: ModelViewerState { project.viewer }
    private var output: ProjectOutput { project.output }
    private var groups: [PartGroup] { PartArrangement.groups(of: output.parts) }
    private var layout: PartsLayout { viewer.effectiveLayout(for: output) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !isCollapsed {
                Picker("Vista delle parti", selection: Binding(get: { viewer.layout }, set: { viewer.layout = $0 })) {
                    ForEach(availableLayouts, id: \.self) { layout in
                        Label(layout.title, systemImage: layout.systemImage).tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(viewer.isAnimating || viewer.compareVersion != nil)
                if layout == .exploded {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .foregroundStyle(.secondary)
                        Slider(value: Binding(get: { viewer.explodeAmount }, set: { viewer.explodeAmount = $0 }), in: 0...2)
                            .accessibilityLabel(Text("Distanza tra le parti"))
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundStyle(.secondary)
                    }
                }
                if groups.count > 1 {
                    partList
                }
                if layout == .plate, output.plateParts.isEmpty {
                    Text("Claude non ha ancora preparato il piatto di stampa: le parti sono affiancate senza ruotarle. Chiedi di prepararlo nella chat.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .controlSize(.small)
        .padding(10)
        .frame(width: isCollapsed ? nil : 250, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    private var availableLayouts: [PartsLayout] {
        output.parts.count > 1 ? PartsLayout.allCases : [.assembled, .plate]
    }

    private var header: some View {
        Button {
            withAnimation(.snappy) { isCollapsed.toggle() }
        } label: {
            HStack(spacing: 6) {
                Label("Parti", systemImage: "square.stack.3d.up")
                    .font(.callout.weight(.semibold))
                if groups.count > 1 {
                    Text(groups.count, format: .number)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Mostra le parti" : "Nascondi le parti")
    }

    private var partList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(groups) { group in
                    row(group)
                }
            }
        }
        .frame(maxHeight: 220)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ group: PartGroup) -> some View {
        let isHidden = viewer.hiddenParts.contains(group.name)
        let isAttached = viewer.attachedParts.contains(group.name)
        return HStack(spacing: 6) {
            Circle()
                .fill(group.color.map { Color(red: Double($0.x), green: Double($0.y), blue: Double($0.z)) } ?? Color.secondary.opacity(0.4))
                .overlay(Circle().strokeBorder(.separator))
                .frame(width: 9, height: 9)
            Text(group.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isHidden ? .tertiary : .primary)
            if group.members.count > 1 {
                Text("×\(group.members.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if layout == .exploded {
                Button {
                    toggle(group.name, in: \.attachedParts)
                } label: {
                    Image(systemName: isAttached ? "link" : "link.badge.plus")
                        .foregroundStyle(isAttached ? Color.accentColor : .secondary)
                }
                .help(isAttached ? "Separa dal resto" : "Tieni unita al resto")
                .accessibilityLabel(Text(isAttached ? "Separa \(group.name)" : "Tieni unita \(group.name)"))
            }
            Button {
                toggle(group.name, in: \.hiddenParts)
            } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .foregroundStyle(isHidden ? .tertiary : .secondary)
            }
            .help(isHidden ? "Mostra" : "Nascondi")
            .accessibilityLabel(Text(isHidden ? "Mostra \(group.name)" : "Nascondi \(group.name)"))
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            isolate(group.name)
        }
    }

    private func toggle(_ name: String, in keyPath: ReferenceWritableKeyPath<ModelViewerState, Set<String>>) {
        if viewer[keyPath: keyPath].contains(name) {
            viewer[keyPath: keyPath].remove(name)
        } else {
            viewer[keyPath: keyPath].insert(name)
        }
    }

    private func isolate(_ name: String) {
        let others = Set(groups.map(\.name)).subtracting([name])
        viewer.hiddenParts = viewer.hiddenParts == others ? [] : others
    }
}
