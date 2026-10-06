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
    let meshID: UUID
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
    let motion: MotionStudy.State?
    let movingParts: Set<String>
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
            scene.animate(parts: parts, movingParts: movingParts, meshID: meshID, motion: motion)
            scene.frameIfNeeded(mesh: mesh, preset: preset, cameraID: cameraID)
        }
        .overlay {
            CameraInputView(scene: scene) { point, size in
                guard let onPick, let hit = scene.pick(at: point, in: size, on: displayedMesh) else { return }
                onPick(hit)
            }
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
    private let grid = Entity()
    private let camera = PerspectiveCamera()
    private var meshID: UUID?
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
        meshID: UUID,
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

    func animate(parts: [NamedMesh], movingParts: Set<String>, meshID: UUID, motion: MotionStudy.State?) {
        guard let motion, !parts.isEmpty else {
            animatedParts.isEnabled = false
            model.isEnabled = true
            interior.isEnabled = !isWireframe
            return
        }
        let appearance = "\(isWireframe)-\(isDark)"
        if animatedMeshID != meshID || animatedAppearance != appearance {
            animatedMeshID = meshID
            animatedAppearance = appearance
            buildAnimatedParts(parts, movingParts: movingParts)
        }
        model.isEnabled = false
        interior.isEnabled = false
        animatedParts.isEnabled = true
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

    private func placeCamera() {
        let direction = SIMD3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
        camera.look(at: target, from: target + direction * distance, upVector: SIMD3(0, 1, 0), relativeTo: root)
    }

    private func addLights() {
        let key = DirectionalLight()
        key.light.intensity = 2600
        key.look(at: .zero, from: SIMD3(60, 120, 90), relativeTo: nil)
        let fill = DirectionalLight()
        fill.light.intensity = 900
        fill.look(at: .zero, from: SIMD3(-90, 40, -60), relativeTo: nil)
        root.addChild(key)
        root.addChild(fill)
    }

    private func show(_ mesh: TriangleMesh) {
        colors = mesh.colors
        guard let resource = Self.resource(for: mesh) else {
            model.model = nil
            interior.model = nil
            return
        }
        model.model = ModelComponent(mesh: resource, materials: surfaceMaterials(for: colors))
        var cut = UnlitMaterial(color: NSColor.systemRed.blended(withFraction: 0.15, of: .black) ?? .systemRed)
        cut.faceCulling = .front
        interior.model = ModelComponent(mesh: resource, materials: Array(repeating: cut, count: colors.count + 1))
        interior.isEnabled = !isWireframe
    }

    private func showGhost(_ mesh: TriangleMesh?) {
        guard let mesh, let resource = Self.resource(for: mesh) else {
            ghostEntity.model = nil
            return
        }
        var material = UnlitMaterial(color: .systemOrange)
        material.blending = .transparent(opacity: 0.6)
        material.faceCulling = .none
        material.triangleFillMode = .lines
        ghostEntity.model = ModelComponent(mesh: resource, materials: Array(repeating: material, count: mesh.colors.count + 1))
    }

    private func showMarkers(_ points: [SIMD3<Float>]) {
        markers.children.removeAll()
        let radius = max(modelRadius * 0.03, 0.4)
        let material = UnlitMaterial(color: .systemOrange)
        let scenePoints = points.map(Self.sceneVector)
        for point in scenePoints {
            let marker = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
            marker.position = point
            markers.addChild(marker)
        }
        guard scenePoints.count == 2 else { return }
        let length = simd_distance(scenePoints[0], scenePoints[1])
        guard length > 0 else { return }
        let line = ModelEntity(mesh: .generateBox(size: SIMD3(radius * 0.5, radius * 0.5, length)), materials: [material])
        let middle = (scenePoints[0] + scenePoints[1]) / 2
        let along = simd_normalize(scenePoints[1] - scenePoints[0])
        let up: SIMD3<Float> = abs(along.y) > 0.99 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
        line.look(at: scenePoints[1], from: middle, upVector: up, relativeTo: markers)
        markers.addChild(line)
    }

    private func surfaceMaterials(for colors: [SIMD4<Float>]) -> [RealityKit.Material] {
        let neutral = isDark
            ? NSColor(red: 0.62, green: 0.70, blue: 0.80, alpha: 1)
            : NSColor(red: 0.55, green: 0.64, blue: 0.75, alpha: 1)
        let partColors = colors.map { NSColor(red: CGFloat($0.x), green: CGFloat($0.y), blue: CGFloat($0.z), alpha: 1) }
        return ([neutral] + partColors).map(surfaceMaterial)
    }

    private static func translucent(_ material: RealityKit.Material) -> RealityKit.Material {
        guard var material = material as? PhysicallyBasedMaterial else { return material }
        material.blending = .transparent(opacity: 0.22)
        material.faceCulling = .none
        return material
    }

    private func surfaceMaterial(_ color: NSColor) -> RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.metallic = 0.15
        material.roughness = 0.55
        material.faceCulling = isWireframe ? .none : .back
        material.triangleFillMode = isWireframe ? .lines : .fill
        return material
    }

    private func rebuildGrid(for mesh: TriangleMesh) {
        grid.children.removeAll()
        let footprint = max(mesh.size.x, mesh.size.y)
        let half = Float(max(100, (Int(footprint * 0.75 / 10) + 1) * 10))
        let minorColor = isDark ? NSColor(white: 1, alpha: 0.10) : NSColor(white: 0, alpha: 0.10)
        let majorColor = isDark ? NSColor(white: 1, alpha: 0.28) : NSColor(white: 0, alpha: 0.28)
        var minor: [SIMD3<Float>] = []
        var major: [SIMD3<Float>] = []
        var offset = -half
        while offset <= half + 0.01 {
            let isMajor = Int(offset.rounded()) % 100 == 0
            let width: Float = isMajor ? 0.5 : 0.25
            let quads = quad(from: SIMD3(offset, 0, -half), to: SIMD3(offset, 0, half), width: width)
                + quad(from: SIMD3(-half, 0, offset), to: SIMD3(half, 0, offset), width: width)
            if isMajor {
                major += quads
            } else {
                minor += quads
            }
            offset += 10
        }
        grid.position.y = -0.05
        grid.addChild(lineEntity(minor, color: minorColor))
        grid.addChild(lineEntity(major, color: majorColor))
        let footprintSize = Self.sceneVector(mesh.size)
        let margin = max(max(mesh.size.x, mesh.size.y) * 0.15, 3)
        let corner = SIMD3<Float>(-footprintSize.x / 2 - margin, 0.05, abs(footprintSize.z) / 2 + margin)
        let axisLength = max(max(mesh.size.x, mesh.size.y, mesh.size.z) * 0.3, 5)
        grid.addChild(axisEntity(from: corner, direction: SIMD3(1, 0, 0), length: axisLength, color: .systemRed))
        grid.addChild(axisEntity(from: corner, direction: SIMD3(0, 0, -1), length: axisLength, color: .systemGreen))
        grid.addChild(axisEntity(from: corner, direction: SIMD3(0, 1, 0), length: axisLength, color: .systemBlue))
    }

    private func quad(from start: SIMD3<Float>, to end: SIMD3<Float>, width: Float) -> [SIMD3<Float>] {
        let along = simd_normalize(end - start)
        let side = simd_cross(along, SIMD3(0, 1, 0)) * width / 2
        return [start - side, end - side, end + side, start - side, end + side, start + side]
    }

    private func lineEntity(_ positions: [SIMD3<Float>], color: NSColor) -> Entity {
        var descriptor = MeshDescriptor(name: "grid")
        descriptor.positions = MeshBuffer(positions)
        descriptor.primitives = .triangles((0..<UInt32(positions.count)).map { $0 })
        var material = UnlitMaterial(color: color.withAlphaComponent(1))
        material.blending = .transparent(opacity: .init(floatLiteral: Float(color.alphaComponent)))
        material.faceCulling = .none
        guard let resource = try? MeshResource.generate(from: [descriptor]) else { return Entity() }
        return ModelEntity(mesh: resource, materials: [material])
    }

    private func axisEntity(from origin: SIMD3<Float>, direction: SIMD3<Float>, length: Float, color: NSColor) -> Entity {
        let thickness = max(length / 40, 0.6)
        let size = direction * length + (SIMD3(repeating: 1) - abs(direction)) * thickness
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [UnlitMaterial(color: color)])
        entity.position = origin + direction * length / 2
        return entity
    }

    private static func resource(for mesh: TriangleMesh) -> MeshResource? {
        guard mesh.triangleCount > 0 else { return nil }
        var descriptor = MeshDescriptor(name: "model")
        descriptor.positions = MeshBuffer(mesh.positions.map(sceneVector))
        descriptor.normals = MeshBuffer(mesh.normals.map(sceneVector))
        descriptor.primitives = .triangles((0..<UInt32(mesh.positions.count)).map { $0 })
        descriptor.materials = .perFace(mesh.faceMaterials)
        return try? MeshResource.generate(from: [descriptor])
    }

    private static func sceneVector(_ vector: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(vector.x, vector.z, -vector.y)
    }

    private static func modelVector(_ vector: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(vector.x, -vector.z, vector.y)
    }
}
