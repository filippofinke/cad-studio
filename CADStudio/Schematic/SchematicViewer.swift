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

    func viewDidResize() {
        if isFitted {
            fit()
        }
    }

    func fit() {
        isFitted = true
        guard let webView, sheetSize.width > 0, sheetSize.height > 0 else { return }
        let available = CGSize(width: webView.bounds.width - 48, height: webView.bounds.height - 48)
        setZoom(min(available.width / sheetSize.width, available.height / sheetSize.height))
    }

    func sheetDidLoad(size: CGSize) {
        sheetSize = size
        if hasLoaded, !isFitted {
            setZoom(zoom)
        } else {
            hasLoaded = true
            fit()
        }
    }

    private func setZoom(_ value: Double, anchor: CGPoint? = nil) {
        zoom = min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        if let anchor {
            webView?.evaluateJavaScript("setZoom(\(zoom), \(anchor.x), \(anchor.y))")
        } else {
            webView?.evaluateJavaScript("setZoom(\(zoom))")
        }
    }
}
