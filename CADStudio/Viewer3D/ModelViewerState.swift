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
            isPlaying = isAnimating
            animationTime = 0
            if isAnimating {
                isSectioning = false
                isMeasuring = false
            }
        }
    }
    var isPlaying = false
    var animationTime = 0.0
    var playbackSpeed = 1.0
    var loopsAnimation = true
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

    func advanceAnimation(by seconds: Double, duration: Double) {
        guard duration > 0 else { return }
        let time = animationTime + seconds * playbackSpeed
        if time < duration {
            animationTime = time
        } else if loopsAnimation {
            animationTime = time.truncatingRemainder(dividingBy: duration)
        } else {
            animationTime = duration
            isPlaying = false
        }
    }

    func togglePlayback(duration: Double) {
        if !isPlaying, animationTime >= duration {
            animationTime = 0
        }
        isPlaying.toggle()
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
