import AppKit
import SwiftUI

final class WorkspaceViewController: NSViewController {
    private let hosts: [Pane: NSViewController]
    private let onFractionChange: ([Bool], Double) -> Void
    private var root: NSViewController?
    private var builtStructure: String?

    init(hosts: [Pane: NSViewController], onFractionChange: @escaping ([Bool], Double) -> Void) {
        self.hosts = hosts
        self.onFractionChange = onFractionChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView()
    }

    func show(_ layout: LayoutNode) {
        guard layout.structure != builtStructure else { return }
        builtStructure = layout.structure
        (root as? PaneSplitViewController)?.dismantle()
        root?.view.removeFromSuperview()
        root?.removeFromParent()
        let controller = makeController(for: layout, path: [])
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.width, .height]
        addChild(controller)
        view.addSubview(controller.view)
        root = controller
    }

    func locate(screenPoint: CGPoint) -> (Pane, DropEdge)? {
        for (pane, host) in hosts {
            guard let window = host.view.window, host.view.superview != nil else { continue }
            let point = host.view.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
            let bounds = host.view.bounds
            guard bounds.contains(point), bounds.width > 0, bounds.height > 0 else { continue }
            let x = point.x / bounds.width
            let y = host.view.isFlipped ? point.y / bounds.height : 1 - point.y / bounds.height
            let distances: [(DropEdge, CGFloat)] = [(.leading, x), (.trailing, 1 - x), (.top, y), (.bottom, 1 - y)]
            let edge = distances.min { $0.1 < $1.1 }?.0 ?? .trailing
            return (pane, edge)
        }
        return nil
    }

    private func makeController(for node: LayoutNode, path: [Bool]) -> NSViewController {
        switch node {
        case .pane(let pane):
            return hosts[pane] ?? NSViewController()
        case .split(let split):
            return PaneSplitViewController(
                first: makeController(for: split.first, path: path + [false]),
                second: makeController(for: split.second, path: path + [true]),
                isVertical: split.axis == .row,
                minimumFirstLength: Self.minimumLength(of: split.first, axis: split.axis),
                minimumSecondLength: Self.minimumLength(of: split.second, axis: split.axis),
                fraction: split.fraction
            ) { [weak self] fraction in
                self?.onFractionChange(path, fraction)
            }
        }
    }

    private static func minimumLength(of node: LayoutNode, axis: LayoutAxis) -> CGFloat {
        if case .pane(.chat) = node, axis == .row {
            return 300
        }
        return axis == .row ? 240 : 140
    }
}
