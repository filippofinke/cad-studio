import Foundation

enum AppSettings {
    static let defaultProjectLocationKey = "defaultProjectLocation"
    static let claudePathKey = "claudePath"
    static let claudeModelKey = "claudeModel"
    static let restrictedBashKey = "restrictedBash"
    static let streamingOutputKey = "streamingOutput"
    static let isolatesClaudeKey = "isolatesClaude"
    static let measurementUnitKey = "measurementUnit"
    static let printerTypeKey = "printerType"
    static let printerModelKey = "printerModel"
    static let hasCompletedSetupKey = "hasCompletedSetup"
    static let defaultLayoutKey = "defaultLayout"

    static var defaultProjectLocation: URL {
        if let path = string(defaultProjectLocationKey) {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var claudePath: URL? {
        string(claudePathKey).map { URL(filePath: NSString(string: $0).expandingTildeInPath) }
    }

    static var claudeModel: String? {
        string(claudeModelKey)
    }

    static var usesRestrictedBash: Bool {
        UserDefaults.standard.bool(forKey: restrictedBashKey)
    }

    static var usesStreamingOutput: Bool {
        UserDefaults.standard.object(forKey: streamingOutputKey) as? Bool ?? true
    }

    static var isolatesClaude: Bool {
        UserDefaults.standard.object(forKey: isolatesClaudeKey) as? Bool ?? true
    }

    static var measurementUnit: MeasurementUnit {
        string(measurementUnitKey).flatMap(MeasurementUnit.init) ?? .regionDefault
    }

    static var printerType: PrinterType {
        string(printerTypeKey).flatMap(PrinterType.init) ?? .fdm
    }

    static var printerModel: String? {
        string(printerModelKey)
    }

    static var hasCompletedSetup: Bool {
        UserDefaults.standard.bool(forKey: hasCompletedSetupKey)
    }

    static var defaultLayout: LayoutNode {
        get {
            UserDefaults.standard.data(forKey: defaultLayoutKey)
                .flatMap { try? JSONDecoder().decode(LayoutNode.self, from: $0) } ?? .chatLeading
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: defaultLayoutKey)
        }
    }

    private static func string(_ key: String) -> String? {
        let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}
