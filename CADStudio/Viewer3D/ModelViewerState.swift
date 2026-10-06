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
