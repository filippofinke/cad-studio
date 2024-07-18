import Foundation
import WebKit

@MainActor
@Observable
final class SchematicViewer {
    static let zoomRange = 0.1...8.0

    private(set) var zoom = 1.0
    var page = 0
    @ObservationIgnored weak var webView: WKWebView?
    @ObservationIgnored private var sheetSize = CGSize.zero
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var isFitted = true

    func zoomIn() {
        isFitted = false
        setZoom(zoom * 1.25)
    }

    func zoomOut() {
        isFitted = false
        setZoom(zoom / 1.25)
    }

    func magnify(by amount: Double, at point: CGPoint) {
        zoom(by: 1 + amount, at: point)
    }

    func zoom(by factor: Double, at point: CGPoint) {
        isFitted = false
        setZoom(zoom * factor, anchor: point)
    }
