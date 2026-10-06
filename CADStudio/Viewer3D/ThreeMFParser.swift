import Foundation
import simd

enum ThreeMFError: LocalizedError {
    case unreadable
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "Il file 3MF non è leggibile.")
        case .empty: String(localized: "Il file 3MF non contiene triangoli.")
        }
    }
}

enum ThreeMFParser {
    static func parse(_ url: URL) throws -> TriangleMesh {
        let document = ThreeMFDocument()
        let parser = XMLParser(data: try modelData(from: url))
        parser.delegate = document
        guard parser.parse() else { throw ThreeMFError.unreadable }
        let mesh = document.mesh()
        guard mesh.triangleCount > 0 else { throw ThreeMFError.empty }
        return mesh
    }

    private static func modelData(from url: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, "3D/3dmodel.model"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { throw ThreeMFError.unreadable }
        return data
    }
}

private final class ThreeMFDocument: NSObject, XMLParserDelegate {
    private struct MaterialReference {
        let group: String
        let index: Int
    }

    private struct Triangle {
        let vertices: (Int, Int, Int)
        let material: MaterialReference?
    }

    private struct Placement {
        let objectID: String
        let transform: simd_float4x4
    }

    private struct MeshObject {
        var vertices: [SIMD3<Float>] = []
        var triangles: [Triangle] = []
        var components: [Placement] = []
        let material: MaterialReference?
    }

    private var millimetersPerUnit: Float = 1
    private var materialGroups: [String: [SIMD4<Float>]] = [:]
    private var objects: [String: MeshObject] = [:]
    private var buildItems: [Placement] = []
    private var currentGroupID: String?
    private var currentObjectID: String?
    private var currentObject: MeshObject?

    func mesh() -> TriangleMesh {
        var mesh = TriangleMesh()
        let roots = buildItems.isEmpty
            ? objects.keys.sorted().map { Placement(objectID: $0, transform: matrix_identity_float4x4) }
            : buildItems
        for root in roots {
            append(root.objectID, transform: root.transform, to: &mesh, depth: 0)
        }
        return mesh
    }

    private func append(_ objectID: String, transform: simd_float4x4, to mesh: inout TriangleMesh, depth: Int) {
        guard depth < 16, let object = objects[objectID] else { return }
        let points = object.vertices.map { vertex in
            let placed = transform * SIMD4(vertex, 1)
            return SIMD3(placed.x, placed.y, placed.z) * millimetersPerUnit
        }
        for triangle in object.triangles {
            let (a, b, c) = triangle.vertices
            guard points.indices.contains(a), points.indices.contains(b), points.indices.contains(c) else { continue }
            mesh.addTriangle(points[a], points[b], points[c], color: color(for: triangle.material ?? object.material))
        }
        for component in object.components {
            append(component.objectID, transform: transform * component.transform, to: &mesh, depth: depth + 1)
        }
    }

    private func color(for reference: MaterialReference?) -> SIMD4<Float>? {
        guard let reference, let colors = materialGroups[reference.group], colors.indices.contains(reference.index) else {
            return nil
        }
        return colors[reference.index]
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        switch localName(elementName) {
        case "model":
            millimetersPerUnit = Self.millimeters(perUnit: attributes["unit"])
        case "basematerials", "colorgroup":
            currentGroupID = attributes["id"]
        case "base":
            appendColor(attributes["displaycolor"])
        case "color":
            appendColor(attributes["color"])
        case "object":
            currentObjectID = attributes["id"]
            currentObject = MeshObject(material: reference(attributes["pid"], attributes["pindex"]))
        case "vertex":
            currentObject?.vertices.append(SIMD3(
                Float(attributes["x"] ?? "") ?? 0,
                Float(attributes["y"] ?? "") ?? 0,
                Float(attributes["z"] ?? "") ?? 0
            ))
        case "triangle":
            guard let a = attributes["v1"].flatMap(Int.init),
                  let b = attributes["v2"].flatMap(Int.init),
                  let c = attributes["v3"].flatMap(Int.init)
            else { return }
            let material = reference(attributes["pid"], attributes["p1"])
            currentObject?.triangles.append(Triangle(vertices: (a, b, c), material: material))
        case "component":
            guard let objectID = attributes["objectid"] else { return }
            currentObject?.components.append(Placement(objectID: objectID, transform: Self.transform(attributes["transform"])))
        case "item":
            guard let objectID = attributes["objectid"] else { return }
            buildItems.append(Placement(objectID: objectID, transform: Self.transform(attributes["transform"])))
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch localName(elementName) {
        case "basematerials", "colorgroup":
            currentGroupID = nil
        case "object":
            if let currentObjectID, let currentObject {
                objects[currentObjectID] = currentObject
            }
            currentObjectID = nil
            currentObject = nil
        default:
            break
        }
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    private func reference(_ group: String?, _ index: String?) -> MaterialReference? {
        guard let group else { return nil }
        return MaterialReference(group: group, index: index.flatMap(Int.init) ?? 0)
    }

    private func appendColor(_ hex: String?) {
        guard let currentGroupID, let color = hex.flatMap(Self.color(fromHex:)) else { return }
        materialGroups[currentGroupID, default: []].append(color)
    }

    private static func color(fromHex hex: String) -> SIMD4<Float>? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6 || digits.count == 8, let value = UInt32(digits, radix: 16) else { return nil }
        let rgba = digits.count == 6 ? value << 8 | 0xFF : value
        return SIMD4(
            Float((rgba >> 24) & 0xFF) / 255,
            Float((rgba >> 16) & 0xFF) / 255,
            Float((rgba >> 8) & 0xFF) / 255,
            Float(rgba & 0xFF) / 255
        )
    }

    private static func transform(_ text: String?) -> simd_float4x4 {
        let values = (text ?? "").split(separator: " ").compactMap { Float($0) }
        guard values.count == 12 else { return matrix_identity_float4x4 }
        return simd_float4x4(columns: (
            SIMD4(values[0], values[1], values[2], 0),
            SIMD4(values[3], values[4], values[5], 0),
            SIMD4(values[6], values[7], values[8], 0),
            SIMD4(values[9], values[10], values[11], 1)
        ))
    }

    private static func millimeters(perUnit unit: String?) -> Float {
        switch unit {
        case "micron": 0.001
        case "centimeter": 10
        case "inch": 25.4
        case "foot": 304.8
        case "meter": 1000
        default: 1
        }
    }
}
