import Foundation

struct ProjectFolder: Hashable, Sendable {
    let root: URL

    var name: String { root.lastPathComponent }

    var modelScript: URL { root.appending(path: "model.py") }
    var references: URL { root.appending(path: "references", directoryHint: .isDirectory) }

    var output: URL { root.appending(path: "output", directoryHint: .isDirectory) }
    var stl: URL { output.appending(path: "model.stl") }
    var threeMF: URL { output.appending(path: "model.3mf") }
    var step: URL { output.appending(path: "model.step") }
    var pdf: URL { output.appending(path: "schematic.pdf") }
    var svg: URL { output.appending(path: "schematic.svg") }
    var png: URL { output.appending(path: "schematic.png") }
    var manifest: URL { output.appending(path: "manifest.json") }
    var animation: URL { output.appending(path: "animation.json") }

    var expectedOutputs: [URL] { [threeMF, stl, step, svg, png, pdf, manifest] }

    var support: URL { root.appending(path: ".cadstudio", directoryHint: .isDirectory) }
    var projectFile: URL { support.appending(path: "project.json") }
    var chatFile: URL { support.appending(path: "chat.json") }
    var logs: URL { support.appending(path: "logs", directoryHint: .isDirectory) }
    var versions: URL { support.appending(path: "versions", directoryHint: .isDirectory) }
}
