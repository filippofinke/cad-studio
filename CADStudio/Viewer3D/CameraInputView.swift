import AppKit
import SwiftUI

struct CameraInputView: NSViewRepresentable {
    let scene: ModelScene
    let onClick: (CGPoint, CGSize) -> Void

    func makeNSView(context: Context) -> CameraInputNSView {
        CameraInputNSView(scene: scene, onClick: onClick)
    }

    func updateNSView(_ view: CameraInputNSView, context: Context) {
        view.onClick = onClick
    }
}

final class CameraInputNSView: NSView {
    private let scene: ModelScene
    var onClick: (CGPoint, CGSize) -> Void
    private var dragDistance: CGFloat = 0

    init(scene: ModelScene, onClick: @escaping (CGPoint, CGSize) -> Void) {
        self.scene = scene
        self.onClick = onClick
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        dragDistance = 0
    }

    override func mouseDragged(with event: NSEvent) {
        dragDistance += abs(event.deltaX) + abs(event.deltaY)
        let delta = CGSize(width: event.deltaX, height: event.deltaY)
        if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.shift) {
            scene.pan(by: delta, viewHeight: bounds.height)
        } else {
            scene.orbit(by: delta)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard dragDistance < 4 else { return }
        onClick(convert(event.locationInWindow, from: nil), bounds.size)
    }

    override func rightMouseDragged(with event: NSEvent) {
        scene.pan(by: CGSize(width: event.deltaX, height: event.deltaY), viewHeight: bounds.height)
    }

    override func otherMouseDragged(with event: NSEvent) {
        scene.pan(by: CGSize(width: event.deltaX, height: event.deltaY), viewHeight: bounds.height)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) {
            scene.pan(by: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY), viewHeight: bounds.height)
            return
        }
        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
        let steps = event.hasPreciseScrollingDeltas ? Float(delta) / 12 : Float(delta)
        scene.zoom(by: pow(0.9, steps))
    }

    override func magnify(with event: NSEvent) {
        scene.zoom(by: 1 / max(1 + Float(event.magnification), 0.1))
    }
}
