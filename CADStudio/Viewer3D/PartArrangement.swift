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
