import SwiftUI
import WebKit

struct SVGWebView: NSViewRepresentable {
    let file: URL
    let revision: String
    let viewer: SchematicViewer

    func makeCoordinator() -> Coordinator {
        Coordinator(viewer: viewer)
    }

    func makeNSView(context: Context) -> SheetWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "sheet")
        let webView = SheetWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.onMagnify = { [weak viewer] amount, point in viewer?.magnify(by: amount, at: point) }
        webView.onResize = { [weak viewer] in viewer?.viewDidResize() }
        viewer.webView = webView
        return webView
    }

    func updateNSView(_ webView: SheetWebView, context: Context) {
        guard context.coordinator.loadedRevision != revision else { return }
        context.coordinator.loadedRevision = revision
        guard let data = try? Data(contentsOf: file) else { return }
        webView.loadHTMLString(Self.page(svg: data), baseURL: nil)
    }

    static func dismantleNSView(_ webView: SheetWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "sheet")
    }

    private static func page(svg: Data) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><style>
        html, body { margin: 0; background: transparent; -webkit-user-select: none; cursor: grab; scrollbar-width: none; }
        ::-webkit-scrollbar { display: none; width: 0; height: 0; }
        body.dragging { cursor: grabbing; }
        body { display: flex; min-height: 100vh; min-width: 100vw; width: max-content; align-items: center; justify-content: center; padding: 24px; box-sizing: border-box; }
        img { display: block; background: #fff; box-shadow: 0 1px 4px rgba(0,0,0,.25), 0 0 0 .5px rgba(0,0,0,.12); -webkit-user-drag: none; }
        </style></head><body>
        <img id="sheet" src="data:image/svg+xml;base64,\(svg.base64EncodedString())">
        <script>
        const sheet = document.getElementById('sheet');
        let sheetWidth = 1123;
        let sheetHeight = 794;
        function setZoom(zoom, x, y) {
            const anchorX = x ?? window.innerWidth / 2;
            const anchorY = y ?? window.innerHeight / 2;
            const before = sheet.getBoundingClientRect();
            const fractionX = before.width > 0 ? (anchorX - before.left) / before.width : 0.5;
            const fractionY = before.height > 0 ? (anchorY - before.top) / before.height : 0.5;
            sheet.style.width = (sheetWidth * zoom) + 'px';
            sheet.style.height = (sheetHeight * zoom) + 'px';
            const after = sheet.getBoundingClientRect();
            window.scrollBy(after.left + fractionX * after.width - anchorX, after.top + fractionY * after.height - anchorY);
        }
        function report() {
            sheetWidth = sheet.naturalWidth || sheetWidth;
            sheetHeight = sheet.naturalHeight || sheetHeight;
            window.webkit.messageHandlers.sheet.postMessage({ width: sheetWidth, height: sheetHeight });
        }
        if (sheet.complete) { report(); } else { sheet.onload = report; }
        document.addEventListener('contextmenu', event => event.preventDefault());
        document.addEventListener('mousedown', event => {
            document.body.classList.add('dragging');
            const move = moved => window.scrollBy(-moved.movementX, -moved.movementY);
            const stop = () => {
                document.body.classList.remove('dragging');
                document.removeEventListener('mousemove', move);
                document.removeEventListener('mouseup', stop);
            };
            document.addEventListener('mousemove', move);
            document.addEventListener('mouseup', stop);
            event.preventDefault();
        });
        document.addEventListener('wheel', event => {
            if (event.shiftKey || event.altKey) { return; }
            event.preventDefault();
            const pixels = event.deltaMode === 1 ? event.deltaY * 16 : event.deltaY;
            const step = Math.max(-0.2, Math.min(0.2, -pixels * 0.0025));
            window.webkit.messageHandlers.sheet.postMessage({ zoom: Math.exp(step), x: event.clientX, y: event.clientY });
        }, { passive: false });
        document.addEventListener('dblclick', () => window.webkit.messageHandlers.sheet.postMessage('fit'));
        </script>
        </body></html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let viewer: SchematicViewer
        var loadedRevision: String?

        init(viewer: SchematicViewer) {
            self.viewer = viewer
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Double], let factor = body["zoom"], let x = body["x"], let y = body["y"] {
                viewer.zoom(by: factor, at: CGPoint(x: x, y: y))
            } else if let size = message.body as? [String: Double], let width = size["width"], let height = size["height"] {
                viewer.sheetDidLoad(size: CGSize(width: width, height: height))
            } else if message.body as? String == "fit" {
                viewer.fit()
            }
        }
    }
}

final class SheetWebView: WKWebView {
    var onMagnify: ((Double, CGPoint) -> Void)?
    var onResize: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?()
    }

    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onMagnify?(event.magnification, CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y))
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.removeAllItems()
    }
}
