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

    func showBed(_ size: SIMD2<Float>?) {
        guard size != bed else { return }
        bed = size
        bedEntity.children.removeAll()
        guard let size else { return }
        let half = size / 2
        let corners = [SIMD3(-half.x, 0.06, half.y), SIMD3(half.x, 0.06, half.y), SIMD3(half.x, 0.06, -half.y), SIMD3(-half.x, 0.06, -half.y)]
        var positions: [SIMD3<Float>] = []
        for index in corners.indices {
            positions += quad(from: corners[index], to: corners[(index + 1) % corners.count], width: max(size.x, size.y) / 250)
        }
        bedEntity.addChild(lineEntity(positions, color: .controlAccentColor))
    }

    func animate(parts: [NamedMesh], partsID: UUID, hidden: Set<String>, study: MotionStudy?, player: MotionPlayer) {
        self.player = player
        guard let study, !parts.isEmpty else {
            self.study = nil
            stopPlayback()
            animatedParts.isEnabled = false
            model.isEnabled = true
            interior.isEnabled = !isWireframe
            return
        }
        self.study = study
        let appearance = "\(isWireframe)-\(isDark)"
        if animatedMeshID != partsID || animatedAppearance != appearance {
            animatedMeshID = partsID
            animatedAppearance = appearance
            buildAnimatedParts(parts, movingParts: study.movingParts)
        }
        model.isEnabled = false
        interior.isEnabled = false
        animatedParts.isEnabled = true
        for (name, part) in partEntities {
            part.entity.isEnabled = !hidden.contains(name)
        }
        posedTime = nil
        startPlayback()
    }

    func stopPlayback() {
        timer?.invalidate()
        timer = nil
    }

    private func startPlayback() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = CACurrentMediaTime()
                self.tick(now - self.lastTick)
                self.lastTick = now
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick(_ deltaTime: Double) {
        guard let study, let player else { return }
        if player.isPlaying {
            player.advance(by: deltaTime, duration: study.duration)
        }
        guard player.time != posedTime else { return }
        posedTime = player.time
        pose(study.state(at: player.time))
    }

    private func pose(_ motion: MotionStudy.State) {
        let colliding = motion.collidingParts
        for (name, part) in partEntities {
            let pose = motion.poses[name] ?? .identity
            part.entity.position = Self.sceneVector(pose.translate)
            part.entity.orientation = simd_quatf(vector: SIMD4(Self.sceneVector(pose.rotate.imag), pose.rotate.real))
            if colliding.contains(name) != collidingParts.contains(name) {
                part.entity.model?.materials = colliding.contains(name) ? part.collision : part.materials
            }
        }
        collidingParts = colliding
    }

    private func buildAnimatedParts(_ parts: [NamedMesh], movingParts: Set<String>) {
        animatedParts.children.removeAll()
        partEntities = [:]
        collidingParts = []
        var collisionMaterial = PhysicallyBasedMaterial()
        collisionMaterial.baseColor = .init(tint: .systemRed)
        collisionMaterial.emissiveColor = .init(color: .systemRed)
        collisionMaterial.emissiveIntensity = 0.6
        collisionMaterial.faceCulling = .none
        for part in parts {
            guard let resource = Self.resource(for: part.mesh) else { continue }
            let materials = movingParts.contains(part.name)
                ? surfaceMaterials(for: part.mesh.colors)
                : surfaceMaterials(for: part.mesh.colors).map(Self.translucent)
            let entity = ModelEntity(mesh: resource, materials: materials)
            animatedParts.addChild(entity)
            partEntities[part.name] = (entity, materials, Array(repeating: collisionMaterial, count: materials.count))
        }
    }

    func pick(at point: CGPoint, in size: CGSize, on mesh: TriangleMesh) -> SIMD3<Float>? {
        guard size.width > 0, size.height > 0 else { return nil }
        let tangent = tan(camera.camera.fieldOfViewInDegrees * .pi / 360)
        let x = (2 * Float(point.x / size.width) - 1) * tangent * Float(size.width / size.height)
        let y = (2 * Float(point.y / size.height) - 1) * tangent
        let direction = simd_normalize(camera.convert(direction: SIMD3(x, y, -1), to: root))
        let origin = camera.position(relativeTo: root) - content.position
        return mesh.firstIntersection(origin: Self.modelVector(origin), direction: Self.modelVector(direction))
    }

    func orbit(by delta: CGSize) {
        yaw -= Float(delta.width) * 0.008
        pitch = min(max(pitch + Float(delta.height) * 0.008, -Self.maximumPitch), Self.maximumPitch)
        placeCamera()
    }

    func zoom(by factor: Float) {
        distance = min(max(distance * factor, modelRadius * 0.1), modelRadius * 200)
        placeCamera()
    }

    func pan(by delta: CGSize, viewHeight: CGFloat) {
        guard viewHeight > 0 else { return }
        let halfAngle = camera.camera.fieldOfViewInDegrees * .pi / 360
        let unitsPerPoint = 2 * distance * tan(halfAngle) / Float(viewHeight)
        let right = camera.convert(direction: SIMD3(1, 0, 0), to: root)
        let up = camera.convert(direction: SIMD3(0, 1, 0), to: root)
        target += (-right * Float(delta.width) + up * Float(delta.height)) * unitsPerPoint
        placeCamera()
    }

    func frameIfNeeded(mesh: TriangleMesh, preset: CameraPreset, cameraID: UUID) {
        guard cameraID != framedCameraID else { return }
        framedCameraID = cameraID
        frame(mesh: mesh, preset: preset)
    }

    private func frame(mesh: TriangleMesh, preset: CameraPreset) {
        let size = Self.sceneVector(mesh.size)
        modelRadius = max(simd_length(size) / 2, 1)
        target = SIMD3(0, size.y / 2, 0)
        let halfAngle = camera.camera.fieldOfViewInDegrees * .pi / 360
        distance = modelRadius / sin(halfAngle) * 1.15
        yaw = preset.yaw
        pitch = preset.pitch
        placeCamera()
    }
