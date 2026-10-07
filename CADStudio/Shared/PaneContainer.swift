import SwiftUI

struct PaneContainer<Content: View>: View {
    let pane: Pane
    let project: Project
    @ViewBuilder var content: Content
    @State private var isHoveringHandle = false

    var body: some View {
        content
            .overlay(alignment: .topLeading) {
                handle
            }
            .overlay {
                dropHighlight
            }
    }

    private var handle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 16)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator))
            .opacity(isHoveringHandle || project.paneDrag?.pane == pane ? 1 : 0.45)
            .padding(6)
            .contentShape(Rectangle())
            .onHover { isHoveringHandle = $0 }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { _ in project.dragPane(pane, to: NSEvent.mouseLocation) }
                    .onEnded { _ in project.dropPane() }
            )
            .help("Trascina per spostare il pannello")
            .accessibilityLabel(Text("Sposta il pannello"))
    }

    @ViewBuilder
    private var dropHighlight: some View {
        if let drag = project.paneDrag, drag.target == pane, let edge = drag.edge {
            GeometryReader { proxy in
                let size = proxy.size
                let rect: CGRect = switch edge {
                case .leading: CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)
                case .trailing: CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height)
                case .top: CGRect(x: 0, y: 0, width: size.width, height: size.height / 2)
                case .bottom: CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2)
                }
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.18))
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: rect.width - 8, height: rect.height - 8)
                    .position(x: rect.midX, y: rect.midY)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        } else if project.paneDrag?.pane == pane {
            Color.accentColor.opacity(0.06)
                .allowsHitTesting(false)
        }
    }
}
