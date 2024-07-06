import RealityKit
import SwiftUI

enum CameraPreset: CaseIterable {
    case iso
    case front
    case top
    case right

    var title: LocalizedStringKey {
        switch self {
        case .iso: "Iso"
        case .front: "Fronte"
        case .top: "Alto"
        case .right: "Destra"
        }
    }

    var yaw: Float {
        switch self {
        case .iso: .pi / 4
        case .front, .top: 0
        case .right: .pi / 2
        }
    }

    var pitch: Float {
        switch self {
        case .iso: 0.6
        case .front, .right: 0
        case .top: ModelScene.maximumPitch
        }
    }
}

struct ModelViewer: View {
    let mesh: TriangleMesh
    let meshID: String
    let displayedMesh: TriangleMesh
    let displayKey: String
    let ghost: TriangleMesh?
    let ghostID: UUID?
    let measurePoints: [SIMD3<Float>]
    let preset: CameraPreset
    let cameraID: UUID
    let showsGrid: Bool
    let showsWireframe: Bool
    let parts: [NamedMesh]
    let partsID: UUID
    let hiddenParts: Set<String>
    let bed: SIMD2<Float>?
    let motion: MotionStudy?
    let player: MotionPlayer
    let onPick: ((SIMD3<Float>) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @State private var scene = ModelScene()

    var body: some View {
        RealityView { content in
            scene.build(mesh: mesh, preset: preset, cameraID: cameraID)
            content.add(scene.root)
        } update: { _ in
            scene.update(
                mesh: mesh,
                meshID: meshID,
                displayedMesh: displayedMesh,
                displayKey: displayKey,
                ghost: ghost,
                ghostID: ghostID,
                measurePoints: measurePoints,
                showsGrid: showsGrid,
                showsWireframe: showsWireframe,
                isDark: colorScheme == .dark
            )
            scene.showBed(bed)
            scene.animate(parts: parts, partsID: partsID, hidden: hiddenParts, study: motion, player: player)
            scene.frameIfNeeded(mesh: mesh, preset: preset, cameraID: cameraID)
        }
        .overlay {
            CameraInputView(scene: scene) { point, size in
                guard let onPick, let hit = scene.pick(at: point, in: size, on: displayedMesh) else { return }
                onPick(hit)
            }
        }
        .onDisappear {
            scene.stopPlayback()
        }
        .background(colorScheme == .dark ? Color(white: 0.13) : Color(white: 0.94))
        .accessibilityLabel(Text("Viewer 3D del modello"))
    }
}

@MainActor
final class ModelScene {
    nonisolated static let maximumPitch: Float = 1.5607

    let root = Entity()
    private let content = Entity()
    private let model = ModelEntity()
    private let interior = ModelEntity()
    private let ghostEntity = ModelEntity()
    private let markers = Entity()
    private let animatedParts = Entity()
    private var animatedMeshID: UUID?
    private var animatedAppearance: String?
    private var partEntities: [String: (entity: ModelEntity, materials: [RealityKit.Material], collision: [RealityKit.Material])] = [:]
    private var collidingParts: Set<String> = []
    private var study: MotionStudy?
    private var player: MotionPlayer?
    private var posedTime: Double?
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0
    private let grid = Entity()
    private let camera = PerspectiveCamera()
    private var meshID: String?
    private let bedEntity = Entity()
    private var bed: SIMD2<Float>?
    private var displayKey: String?
    private var ghostID: UUID?
    private var measurePoints: [SIMD3<Float>] = []
    private var isWireframe = false
    private var isDark = false
    private var colors: [SIMD4<Float>] = []
    private var target = SIMD3<Float>.zero
    private var yaw: Float = 0
    private var pitch: Float = 0
    private var distance: Float = 100
    private var modelRadius: Float = 10
    private var framedCameraID: UUID?

    func build(mesh: TriangleMesh, preset: CameraPreset, cameraID: UUID) {
        framedCameraID = cameraID
        content.addChild(model)
        content.addChild(interior)
        content.addChild(ghostEntity)
        content.addChild(markers)
        content.addChild(animatedParts)
        content.addChild(bedEntity)
        root.addChild(content)
        root.addChild(grid)
        addLights()
        camera.camera.near = 1
        camera.camera.far = 100_000
        camera.camera.fieldOfViewInDegrees = 35
        root.addChild(camera)
        frame(mesh: mesh, preset: preset)
    }

    func update(
        mesh: TriangleMesh,
        meshID: String,
        displayedMesh: TriangleMesh,
        displayKey: String,
        ghost: TriangleMesh?,
        ghostID: UUID?,
        measurePoints: [SIMD3<Float>],
        showsGrid: Bool,
        showsWireframe: Bool,
        isDark: Bool
    ) {
        let appearanceChanged = showsWireframe != isWireframe || isDark != self.isDark
        isWireframe = showsWireframe
        self.isDark = isDark
        let meshChanged = meshID != self.meshID
        if meshChanged || appearanceChanged {
            self.meshID = meshID
            let center = Self.sceneVector(mesh.center)
            content.position = SIMD3(-center.x, -Self.sceneVector(mesh.minimum).y, -center.z)
            rebuildGrid(for: mesh)
        }
        let key = "\(meshID)-\(displayKey)"
        if key != self.displayKey || appearanceChanged {
            self.displayKey = key
            show(displayedMesh)
        }
        if ghostID != self.ghostID || meshChanged {
            self.ghostID = ghostID
            showGhost(ghost)
        }
        if measurePoints != self.measurePoints || meshChanged {
            self.measurePoints = measurePoints
            showMarkers(measurePoints)
        }
        grid.isEnabled = showsGrid
    }
