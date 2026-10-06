import Foundation

enum ToolSummary {
    static func title(name: String, input: JSONValue, root: URL, python: URL) -> String {
        switch name {
        case "Bash":
            return String(localized: "Esegue \(shortCommand(input["command"]?.string ?? "", root: root, python: python))")
        case "Write":
            return String(localized: "Crea \(file(input, root: root))")
        case "Edit", "MultiEdit":
            return String(localized: "Modifica \(file(input, root: root))")
        case "Read":
            return String(localized: "Legge \(file(input, root: root))")
        case "Glob":
            return String(localized: "Cerca file \(input["pattern"]?.string ?? "")")
        case "Grep":
            return String(localized: "Cerca “\(input["pattern"]?.string ?? "")”")
        case "TodoWrite":
            return String(localized: "Aggiorna il piano di lavoro")
        default:
            return name
        }
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
