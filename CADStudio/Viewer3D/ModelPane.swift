import simd
import SwiftUI

struct ModelPane: View {
    let project: Project
    @FocusState private var isFocused: Bool
    @AppStorage(AppSettings.measurementUnitKey) private var unitName = MeasurementUnit.regionDefault.rawValue

    private var unit: MeasurementUnit { MeasurementUnit(rawValue: unitName) ?? .millimeters }
    private var output: ProjectOutput { project.output }
    private var viewer: ModelViewerState { project.viewer }

    private var motionStudy: MotionStudy? {
        output.parts.count > 1 ? output.motionStudy : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    if viewer.isMeasuring, output.mesh != nil {
                        measurementBadge
                    }
                }
                .overlay(alignment: .topLeading) {
                    if output.mesh != nil, output.parts.count > 1 || !output.plateParts.isEmpty {
                        PartsOverlay(project: project)
                            .padding(.leading, 10)
                            .padding(.top, 32)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if project.areParametersVisible, output.mesh != nil, !project.parameters.isEmpty {
                        ParametersOverlay(project: project)
                            .padding(10)
                    }
                }
                .overlay(alignment: .bottom) {
                    if viewer.isAnimating, let motionStudy {
                        MotionControls(player: viewer.player, study: motionStudy)
                    } else if viewer.isSectioning, output.mesh != nil {
                        sectionControls
                    }
                }
            PaneStatusBar(info: info) {
                controls
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.escape) {
            guard viewer.isMeasuring else { return .ignored }
            viewer.clearMeasurement()
            return .handled
        }
        .onChange(of: project.focusRequest) { _, request in
            if request?.pane == .model3D {
                isFocused = true
            }
        }
        .onChange(of: output.meshID) {
            if let mesh = output.mesh {
                viewer.meshDidChange(size: mesh.size)
            }
        }
        .onChange(of: motionStudy == nil) { _, isMissing in
            if isMissing, viewer.isAnimating {
                viewer.isAnimating = false
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let assembled = output.mesh {
            let arranged = viewer.arrangedMesh(of: output)
            let mesh = arranged.triangleCount > 0 ? arranged : assembled
            ModelViewer(
                mesh: mesh,
                meshID: viewer.sceneID(for: output),
                displayedMesh: viewer.displayedMesh(of: arranged),
                displayKey: "\(viewer.arrangementRevision(for: output))-\(viewer.displayKey)",
                ghost: viewer.compareVersion == nil ? nil : output.comparisonMesh,
                ghostID: viewer.compareVersion == nil ? nil : output.comparisonID,
                measurePoints: viewer.measurePoints,
                preset: viewer.preset,
                cameraID: viewer.cameraID,
                showsGrid: viewer.showsGrid,
                showsWireframe: viewer.showsWireframe,
                parts: output.parts,
                partsID: output.meshID,
                hiddenParts: hiddenMembers,
                bed: viewer.effectiveLayout(for: output) == .plate ? output.manifest?.bed : nil,
                motion: viewer.isAnimating ? motionStudy : nil,
                player: viewer.player,
                onPick: viewer.isMeasuring ? { viewer.addMeasurePoint($0) } : nil
            )
        } else if let error = output.meshError {
            ContentUnavailableView {
                Label("Modello non leggibile", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            ContentUnavailableView {
                Label("Nessun modello", systemImage: "cube.transparent")
            } description: {
                Text("Descrivi un oggetto nella chat per iniziare")
            }
        }
    }

    private var hiddenMembers: Set<String> {
        Set(PartArrangement.groups(of: output.parts).filter { viewer.hiddenParts.contains($0.name) }.flatMap(\.members))
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker("Vista", selection: Binding(get: { viewer.preset }, set: { viewer.show($0) })) {
                ForEach(CameraPreset.allCases, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            toggle(isOn: Binding(get: { viewer.showsGrid }, set: { viewer.showsGrid = $0 }), systemImage: "grid", title: "Griglia", help: "Mostra la griglia")
            toggle(isOn: Binding(get: { viewer.showsWireframe }, set: { viewer.showsWireframe = $0 }), systemImage: "cube.transparent", title: "Wireframe", help: "Mostra il wireframe")
            toggle(isOn: Binding(get: { viewer.isMeasuring }, set: { viewer.isMeasuring = $0 }), systemImage: "ruler", title: "Misura", help: "Misura la distanza tra due punti")
                .disabled(viewer.isAnimating)
            toggle(isOn: Binding(get: { viewer.isSectioning }, set: { viewer.isSectioning = $0 }), systemImage: "square.split.diagonal", title: "Sezione", help: "Mostra una sezione del modello")
                .disabled(viewer.isAnimating)
            if motionStudy != nil {
                toggle(isOn: Binding(get: { viewer.isAnimating }, set: { viewer.isAnimating = $0 }), systemImage: "play.circle", title: "Animazione", help: "Riproduci l’animazione con la simulazione fisica")
            } else if output.parts.count > 1 {
                Button {
                    project.send(String(localized: "Anima il movimento di questo meccanismo con una simulazione fisica."))
                } label: {
                    Image(systemName: "play.circle")
                }
                .disabled(project.isBusy)
                .help("Chiedi a Claude di simulare e animare il meccanismo")
                .accessibilityLabel(Text("Crea animazione"))
            }
            colorLegend
        }
        .buttonStyle(.borderless)
        .disabled(output.mesh == nil)
    }

    private func toggle(isOn: Binding<Bool>, systemImage: String, title: LocalizedStringKey, help: LocalizedStringKey) -> some View {
        Toggle(isOn: isOn) {
            Image(systemName: systemImage)
        }
        .toggleStyle(.button)
        .help(help)
        .accessibilityLabel(Text(title))
    }

    private var measurementBadge: some View {
        Group {
            if viewer.measurePoints.count == 2 {
                let delta = abs(viewer.measurePoints[1] - viewer.measurePoints[0])
                Text("\(length(simd_length(delta))) · ΔX \(length(delta.x)) · ΔY \(length(delta.y)) · ΔZ \(length(delta.z))")
                    .fontDesign(.monospaced)
                    .textSelection(.enabled)
            } else {
                Text(viewer.measurePoints.isEmpty ? "Fai clic su un punto del modello" : "Fai clic sul secondo punto")
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .padding(10)
    }

    private var sectionControls: some View {
        HStack(spacing: 10) {
            Picker("Asse", selection: Binding(get: { viewer.sectionAxis }, set: { viewer.sectionAxis = $0 })) {
                ForEach(SectionAxis.allCases, id: \.self) { axis in
                    Text(axis.title).tag(axis)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Slider(value: Binding(get: { viewer.sectionPosition }, set: { viewer.sectionPosition = $0 }), in: 0.001...0.999)
                .frame(width: 220)
                .accessibilityLabel(Text("Posizione della sezione"))
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .padding(10)
    }

    private var colorLegend: some View {
        HStack(spacing: 3) {
            ForEach(Array((output.mesh?.colors ?? []).prefix(12).enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(Color(red: Double(color.x), green: Double(color.y), blue: Double(color.z)))
                    .overlay(Circle().strokeBorder(.separator))
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(output.mesh?.colors.count ?? 0) colori"))
    }

    private var info: String {
        guard let mesh = output.mesh else { return "" }
        let size = mesh.size
        return "\(length(size.x, symbol: false)) × \(length(size.y, symbol: false)) × \(length(size.z))"
    }

    private func length(_ millimeters: Float, symbol: Bool = true) -> String {
        let format = FloatingPointFormatStyle<Float>.number.precision(.fractionLength(unit.fractionDigits))
        let value = (millimeters / unit.millimetersPerUnit).formatted(format)
        return symbol ? "\(value) \(unit.symbol)" : value
    }
}
