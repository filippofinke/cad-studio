import Foundation
import simd

enum SectionAxis: Int, CaseIterable {
    case x
    case y
    case z

    var title: String {
        switch self {
        case .x: "X"
        case .y: "Y"
        case .z: "Z"
        }
    }
}

@MainActor
@Observable
final class ModelViewerState {
    var preset = CameraPreset.iso
    var showsGrid = true
    var showsWireframe = false
    var isSectioning = false
    var sectionAxis = SectionAxis.x
    var sectionPosition = 0.5
    var compareVersion: Int?
    var isAnimating = false {
        didSet {
            player.time = 0
            player.isPlaying = isAnimating
            if isAnimating {
                isSectioning = false
                isMeasuring = false
            }
        }
    }
    let player = MotionPlayer()
    var layout = PartsLayout(rawValue: UserDefaults.standard.string(forKey: "partsLayout") ?? "") ?? .exploded {
        didSet {
            UserDefaults.standard.set(layout.rawValue, forKey: "partsLayout")
            measurePoints = []
            cameraID = UUID()
        }
    }
    var explodeAmount = 1.0
    var hiddenParts: Set<String> = []
    var attachedParts: Set<String> = []
    @ObservationIgnored private var arrangementKey: String?
    @ObservationIgnored private var arrangement = TriangleMesh()
    var isMeasuring = false {
        didSet { measurePoints = [] }
    }
    private(set) var measurePoints: [SIMD3<Float>] = []
    private(set) var cameraID = UUID()
    private var framedSize: SIMD3<Float>?

    func show(_ preset: CameraPreset) {
        self.preset = preset
        cameraID = UUID()
    }

    func fitToView() {
        cameraID = UUID()
    }

    func addMeasurePoint(_ point: SIMD3<Float>) {
        if measurePoints.count == 2 {
            measurePoints = []
        }
        measurePoints.append(point)
    }

    func clearMeasurement() {
        measurePoints = []
    }

    func effectiveLayout(for output: ProjectOutput) -> PartsLayout {
        if isAnimating || compareVersion != nil {
            return .assembled
        }
        if layout == .exploded, output.parts.count < 2 {
            return .assembled
        }
        return layout
    }

    func sceneID(for output: ProjectOutput) -> String {
        let layout = effectiveLayout(for: output)
        return "\(output.meshID)-\(layout.rawValue)-\(layout == .plate ? output.plateID.uuidString : "")"
    }

    func arrangementRevision(for output: ProjectOutput) -> String {
        "\(sceneID(for: output))-\(explodeAmount)-\(hiddenParts.sorted())-\(attachedParts.sorted())"
    }

    func arrangedMesh(of output: ProjectOutput) -> TriangleMesh {
        guard let mesh = output.mesh else { return TriangleMesh() }
        let layout = effectiveLayout(for: output)
        guard !output.parts.isEmpty, layout != .assembled || !hiddenParts.isEmpty else { return mesh }
        let key = arrangementRevision(for: output)
        if key != arrangementKey {
            arrangementKey = key
            arrangement = PartArrangement.arrange(
                parts: output.parts,
                plateParts: output.plateParts,
                layout: layout,
                explode: Float(explodeAmount),
                hidden: hiddenParts,
                attached: attachedParts
            )
        }
        return arrangement
    }

    func displayedMesh(of mesh: TriangleMesh) -> TriangleMesh {
        guard isSectioning else { return mesh }
        let axis = sectionAxis.rawValue
        let value = mesh.minimum[axis] + (mesh.maximum[axis] - mesh.minimum[axis]) * Float(sectionPosition)
        return mesh.clipped(axis: axis, at: value, keepsBelow: sectionAxis != .y)
    }

    var displayKey: String {
        isSectioning ? "\(sectionAxis.rawValue)-\(sectionPosition)" : "full"
    }

    func meshDidChange(size: SIMD3<Float>) {
        measurePoints = []
        defer { framedSize = size }
        guard let framedSize else { return }
        let previous = max(simd_length(framedSize), 0.001)
        if abs(simd_length(size) - previous) / previous > 0.5 {
            cameraID = UUID()
        }
    }
}
