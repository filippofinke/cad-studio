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
