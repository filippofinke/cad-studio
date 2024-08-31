import AppKit
import UniformTypeIdentifiers

enum Attachments {
    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    static func urls(from pasteboard: NSPasteboard) -> [URL] {
        if let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
            return files
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let url = savedImage(data) {
                return [url]
            }
        }
        return []
    }

    static func savedImage(_ data: Data) -> URL? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(path: "CAD Studio Attachments", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = folder.appending(path: "Pasted image \(formatter.string(from: .now)).png")
        return (try? png.write(to: url)) == nil ? nil : url
    }
}
