import Foundation

enum DropEdge {
    case leading
    case trailing
    case top
    case bottom
}

enum LayoutAxis: String, Codable, Sendable {
    case row
    case column
}

struct LayoutSplit: Codable, Equatable, Sendable {
    var axis: LayoutAxis
    var first: LayoutNode
    var second: LayoutNode
    var fraction: Double
}

indirect enum LayoutNode: Codable, Equatable, Sendable {
    case pane(Pane)
    case split(LayoutSplit)

    static let chatLeading = LayoutNode.split(LayoutSplit(
        axis: .row,
        first: .pane(.chat),
        second: .split(LayoutSplit(axis: .column, first: .pane(.model3D), second: .pane(.schematic), fraction: 0.6)),
        fraction: 0.34
    ))

    static let chatTrailing = LayoutNode.split(LayoutSplit(
        axis: .row,
        first: .split(LayoutSplit(axis: .column, first: .pane(.model3D), second: .pane(.schematic), fraction: 0.6)),
        second: .pane(.chat),
        fraction: 0.66
    ))

    static let chatBottom = LayoutNode.split(LayoutSplit(
        axis: .column,
        first: .split(LayoutSplit(axis: .row, first: .pane(.model3D), second: .pane(.schematic), fraction: 0.6)),
        second: .pane(.chat),
        fraction: 0.62
    ))

    static let threeColumns = LayoutNode.split(LayoutSplit(
        axis: .row,
        first: .pane(.chat),
        second: .split(LayoutSplit(axis: .row, first: .pane(.model3D), second: .pane(.schematic), fraction: 0.55)),
        fraction: 0.28
    ))

    var structure: String {
        switch self {
        case .pane(let pane):
            pane.rawValue
        case .split(let split):
            "\(split.axis.rawValue)(\(split.first.structure),\(split.second.structure))"
        }
    }

    func removing(_ pane: Pane) -> LayoutNode? {
        switch self {
        case .pane(let current):
            return current == pane ? nil : self
        case .split(var split):
            guard let first = split.first.removing(pane) else { return split.second }
            guard let second = split.second.removing(pane) else { return split.first }
            split.first = first
            split.second = second
            return .split(split)
        }
    }

    func moving(_ pane: Pane, to edge: DropEdge, of target: Pane) -> LayoutNode {
        guard pane != target, let remaining = removing(pane) else { return self }
        let placesFirst = edge == .leading || edge == .top
        let axis: LayoutAxis = edge == .leading || edge == .trailing ? .row : .column
        let moved = LayoutNode.pane(pane)
        let stays = LayoutNode.pane(target)
        let movedShare = pane == .chat ? 0.34 : 0.5
        let split = LayoutSplit(
            axis: axis,
            first: placesFirst ? moved : stays,
            second: placesFirst ? stays : moved,
            fraction: placesFirst ? movedShare : 1 - movedShare
        )
        return remaining.replacing(target, with: .split(split))
    }

    func updatingFraction(at path: [Bool], to fraction: Double) -> LayoutNode {
        guard case .split(var split) = self else { return self }
        guard let step = path.first else {
            split.fraction = fraction
            return .split(split)
        }
        let rest = Array(path.dropFirst())
        if step {
            split.second = split.second.updatingFraction(at: rest, to: fraction)
        } else {
            split.first = split.first.updatingFraction(at: rest, to: fraction)
        }
        return .split(split)
    }

    func contains(_ pane: Pane) -> Bool {
        switch self {
        case .pane(let current): current == pane
        case .split(let split): split.first.contains(pane) || split.second.contains(pane)
        }
    }

    private func replacing(_ target: Pane, with node: LayoutNode) -> LayoutNode {
        switch self {
        case .pane(let current):
            return current == target ? node : self
        case .split(var split):
            split.first = split.first.replacing(target, with: node)
            split.second = split.second.replacing(target, with: node)
            return .split(split)
        }
    }
}
