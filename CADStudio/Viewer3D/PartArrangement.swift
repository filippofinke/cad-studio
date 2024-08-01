import simd
import SwiftUI

enum PartsLayout: String, CaseIterable {
    case assembled
    case exploded
    case plate

    var title: LocalizedStringKey {
        switch self {
        case .assembled: "Montato"
        case .exploded: "Esploso"
        case .plate: "Piatto"
        }
    }

    var systemImage: String {
        switch self {
        case .assembled: "cube"
        case .exploded: "square.3.layers.3d.down.right"
        case .plate: "square.grid.3x3.bottomright.filled"
        }
    }
}

struct PartGroup: Identifiable {
    let name: String
    let members: [String]
    let color: SIMD4<Float>?

    var id: String { name }
}

enum PartArrangement {
    static func groupName(of part: String) -> String {
        let base = part.replacing(/[_\-\s]?\d+$/, with: "")
        return base.isEmpty ? part : base
    }

    static func groups(of parts: [NamedMesh]) -> [PartGroup] {
        let counts = Dictionary(grouping: parts.map(\.name), by: groupName).mapValues(\.count)
        var groups: [PartGroup] = []
        for part in parts {
            let base = groupName(of: part.name)
            let name = (counts[base] ?? 0) > 1 ? base : part.name
            if let index = groups.firstIndex(where: { $0.name == name }) {
                let group = groups[index]
                groups[index] = PartGroup(name: name, members: group.members + [part.name], color: group.color)
            } else {
                groups.append(PartGroup(name: name, members: [part.name], color: part.mesh.colors.first))
            }
        }
        return groups
    }

    static func arrange(
        parts: [NamedMesh],
        plateParts: [NamedMesh],
        layout: PartsLayout,
        explode: Float,
        hidden: Set<String>,
        attached: Set<String>
    ) -> TriangleMesh {
        let groupOfPart = Dictionary(uniqueKeysWithValues: groups(of: parts).flatMap { group in group.members.map { ($0, group.name) } })
        func group(_ name: String) -> String { groupOfPart[name] ?? groupName(of: name) }
        var mesh = TriangleMesh()
        switch layout {
        case .assembled:
            for part in parts where !hidden.contains(group(part.name)) {
                mesh.append(part.mesh)
            }
        case .exploded:
            let offsets = explodedOffsets(parts: parts, group: group, explode: explode, attached: attached)
            for part in parts where !hidden.contains(group(part.name)) {
                mesh.append(part.mesh, offset: offsets[group(part.name)] ?? .zero)
            }
            if mesh.triangleCount > 0 {
                let assembledFloor = parts.map(\.mesh.minimum.z).min() ?? 0
                let lift = SIMD3<Float>(0, 0, assembledFloor - mesh.minimum.z)
                if lift.z != 0 {
                    var lifted = TriangleMesh()
                    lifted.append(mesh, offset: lift)
                    mesh = lifted
                }
            }
        case .plate:
            let source = plateParts.isEmpty ? flatLayout(parts) : plateParts
            for part in source where !hidden.contains(group(part.name)) {
                mesh.append(part.mesh)
            }
        }
        return mesh
    }

    private static func explodedOffsets(
        parts: [NamedMesh],
        group: (String) -> String,
        explode: Float,
        attached: Set<String>
    ) -> [String: SIMD3<Float>] {
        var bounds: [String: (SIMD3<Float>, SIMD3<Float>)] = [:]
        var order: [String] = []
        for part in parts where part.mesh.triangleCount > 0 {
            let name = group(part.name)
            if let current = bounds[name] {
                bounds[name] = (simd_min(current.0, part.mesh.minimum), simd_max(current.1, part.mesh.maximum))
            } else {
                bounds[name] = (part.mesh.minimum, part.mesh.maximum)
                order.append(name)
            }
        }
        guard let anchor = order.max(by: { volume(bounds[$0]) < volume(bounds[$1]) }), let anchorBox = bounds[anchor] else {
            return [:]
        }
        let anchorCenter = (anchorBox.0 + anchorBox.1) / 2
        let overall = bounds.values.reduce(anchorBox) { (simd_min($0.0, $1.0), simd_max($0.1, $1.1)) }
        let gap = max(simd_length(overall.1 - overall.0) * 0.06, 2)
        var placed: [(SIMD3<Float>, SIMD3<Float>)] = [anchorBox]
        var offsets: [String: SIMD3<Float>] = [:]
        let others = order
            .filter { $0 != anchor }
            .sorted { distance(bounds[$0], to: anchorCenter) < distance(bounds[$1], to: anchorCenter) }
        for name in others {
            guard let box = bounds[name] else { continue }
            if attached.contains(name) {
                placed.append(box)
                continue
            }
            let direction = dominantAxis((box.0 + box.1) / 2 - anchorCenter)
            let step = max(simd_length(box.1 - box.0) * 0.05, 0.5)
            var travel: Float = 0
            while travel < 10_000, placed.contains(where: { overlaps(box, $0, shift: direction * travel, margin: gap) }) {
                travel += step
            }
            let shift = direction * (travel + gap)
            placed.append((box.0 + shift, box.1 + shift))
            offsets[name] = shift * explode
        }
        return offsets
    }

    private static func volume(_ box: (SIMD3<Float>, SIMD3<Float>)?) -> Float {
        guard let box else { return 0 }
        let size = box.1 - box.0
        return size.x * size.y * size.z
    }

    private static func distance(_ box: (SIMD3<Float>, SIMD3<Float>)?, to point: SIMD3<Float>) -> Float {
        guard let box else { return 0 }
        return simd_distance((box.0 + box.1) / 2, point)
    }

    private static func dominantAxis(_ vector: SIMD3<Float>) -> SIMD3<Float> {
        let magnitude = abs(vector)
        guard max(magnitude.x, magnitude.y, magnitude.z) > 0.01 else { return SIMD3(0, 0, 1) }
        if magnitude.z >= magnitude.x, magnitude.z >= magnitude.y {
            return SIMD3(0, 0, vector.z > 0 ? 1 : -1)
        }
        if magnitude.x >= magnitude.y {
            return SIMD3(vector.x > 0 ? 1 : -1, 0, 0)
        }
        return SIMD3(0, vector.y > 0 ? 1 : -1, 0)
    }

    private static func overlaps(
        _ box: (SIMD3<Float>, SIMD3<Float>),
        _ other: (SIMD3<Float>, SIMD3<Float>),
        shift: SIMD3<Float>,
        margin: Float
    ) -> Bool {
        let minimum = box.0 + shift
        let maximum = box.1 + shift
        return all(minimum .< other.1 + margin * 0.5) && all(maximum .> other.0 - margin * 0.5)
    }

    private static func flatLayout(_ parts: [NamedMesh]) -> [NamedMesh] {
        let gap: Float = 5
        let items = parts.filter { $0.mesh.triangleCount > 0 }
        let area = items.reduce(Float(0)) { $0 + ($1.mesh.size.x + gap) * ($1.mesh.size.y + gap) }
        let rowWidth = max(area.squareRoot() * 1.3, items.map(\.mesh.size.x).max() ?? 0)
        var placed: [NamedMesh] = []
        var cursor = SIMD2<Float>(0, 0)
        var rowDepth: Float = 0
        for part in items.sorted(by: { $0.mesh.size.y > $1.mesh.size.y }) {
            let size = part.mesh.size
            if cursor.x > 0, cursor.x + size.x > rowWidth {
                cursor = SIMD2(0, cursor.y + rowDepth + gap)
                rowDepth = 0
            }
            var moved = TriangleMesh()
            moved.append(part.mesh, offset: SIMD3(cursor.x, cursor.y, 0) - part.mesh.minimum)
            placed.append(NamedMesh(name: part.name, mesh: moved))
            cursor.x += size.x + gap
            rowDepth = max(rowDepth, size.y)
        }
        let maximum = placed.reduce(SIMD3<Float>(repeating: 0)) { simd_max($0, $1.mesh.maximum) }
        let shift = SIMD3(-maximum.x / 2, -maximum.y / 2, 0)
        return placed.map { part in
            var centered = TriangleMesh()
            centered.append(part.mesh, offset: shift)
            return NamedMesh(name: part.name, mesh: centered)
        }
    }
}
