import Foundation

enum ToolSummary {
    static func title(name: String, input: JSONValue, root: URL, python: URL) -> String {
        switch name {
        case "Bash":
            return commandTitle(shortCommand(input["command"]?.string ?? "", root: root, python: python))
        case "Write":
            let path = file(input, root: root)
            if path.isEmpty { return String(localized: "Scrive un file") }
            return isModel(path) ? String(localized: "Scrive il modello") : String(localized: "Prepara un file di supporto")
        case "Edit", "MultiEdit":
            return isModel(file(input, root: root)) ? String(localized: "Modifica il modello") : String(localized: "Modifica un file di supporto")
        case "Read":
            return readTitle(file(input, root: root))
        case "Glob", "Grep":
            return String(localized: "Cerca nel progetto")
        case "TodoWrite":
            return String(localized: "Aggiorna il piano di lavoro")
        case "WebSearch", "WebFetch":
            return String(localized: "Cerca sul web")
        default:
            return String(localized: "Lavora sul progetto")
        }
    }

    private static func isModel(_ path: String) -> Bool {
        (path as NSString).lastPathComponent == "model.py"
    }

    private static func readTitle(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent.lowercased()
        let ext = (name as NSString).pathExtension
        if path.isEmpty { return String(localized: "Legge un file") }
        if path.hasPrefix("references/") { return String(localized: "Studia il riferimento") }
        if isModel(path) { return String(localized: "Rilegge il modello") }
        if name.hasPrefix("schematic") || ext == "pdf" { return String(localized: "Controlla il disegno") }
        if name == "manifest.json" { return String(localized: "Controlla i risultati") }
        if ["png", "jpg", "jpeg", "svg", "webp"].contains(ext) { return String(localized: "Controlla un'anteprima") }
        return String(localized: "Legge un file")
    }

    private static func commandTitle(_ command: String) -> String {
        let text = command.trimmingCharacters(in: .whitespaces)
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        let tool = (words.first.map { ($0 as NSString).lastPathComponent }) ?? ""
        if text.isEmpty { return String(localized: "Lavora sul progetto") }
        if text.contains("pip install") || tool == "uv" { return String(localized: "Installa i componenti") }
        if tool.hasPrefix("python") {
            return words.dropFirst().first == "model.py" ? String(localized: "Compila il modello") : String(localized: "Analizza il modello")
        }
        if ["rsvg-convert", "sips", "magick", "convert", "qlmanage"].contains(tool) { return String(localized: "Prepara un'anteprima") }
        if ["ls", "cat", "head", "tail", "grep", "rg", "find", "wc", "file", "stat"].contains(tool) || (tool == "sed" && !text.contains(" -i")) {
            return String(localized: "Esamina i file")
        }
        if ["sed", "perl"].contains(tool), text.contains("model.py") { return String(localized: "Modifica il modello") }
        if ["sed", "mv", "cp", "rm", "mkdir", "touch", "perl"].contains(tool) { return String(localized: "Sistema i file") }
        return String(localized: "Lavora sul progetto")
    }

    static func liveTitle(name: String, json: String, root: URL, python: URL) -> String {
        var fields: [String: JSONValue] = [:]
        for key in ["file_path", "pattern"] {
            if let value = partialString(key, in: json), json.contains("\"\(key)\":\"\(value)\"") || json.contains("\"\(key)\": \"\(value)\"") {
                fields[key] = .string(value)
            }
        }
        if let command = partialString("command", in: json) {
            fields["command"] = .string(command)
        }
        let title = Self.title(name: name, input: .object(fields), root: root, python: python)
        guard name == "Write", let content = partialString("content", in: json) else { return title }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).count
        return String(localized: "\(title) · \(lines) righe")
    }

    static func livePreview(name: String, json: String) -> String? {
        let key = name == "Write" ? "content" : name == "Edit" ? "new_string" : nil
        guard let key, let content = partialString(key, in: json) else { return nil }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.suffix(4).joined(separator: "\n")
    }

    private static func partialString(_ key: String, in json: String) -> String? {
        guard let keyRange = json.range(of: "\"\(key)\"") else { return nil }
        var rest = json[keyRange.upperBound...].drop { $0 == " " || $0 == ":" }
        guard rest.first == "\"" else { return nil }
        rest = rest.dropFirst()
        var value = ""
        var escaping = false
        for character in rest {
            if escaping {
                switch character {
                case "n": value.append("\n")
                case "t": value.append("\t")
                default: value.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == "\"" {
                break
            } else {
                value.append(character)
            }
        }
        return value
    }

    static func inputText(name: String, input: JSONValue) -> String {
        if name == "Bash", let command = input["command"]?.string {
            return command
        }
        return input.displayText
    }

    private static func shortCommand(_ command: String, root: URL, python: URL) -> String {
        var command = command
            .replacingOccurrences(of: ClaudeRunner.quotedPython(python), with: "python")
            .replacingOccurrences(of: python.path, with: "python")
            .split(separator: "\n").first.map(String.init) ?? ""
        if command.hasPrefix("cd "), command.contains(root.path),
           let separator = command.range(of: "&&") ?? command.range(of: ";") {
            command = String(command[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return command
    }

    private static func file(_ input: JSONValue, root: URL) -> String {
        let path = input["file_path"]?.string ?? input["path"]?.string ?? ""
        let prefix = root.path + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : (path as NSString).lastPathComponent
    }
}
