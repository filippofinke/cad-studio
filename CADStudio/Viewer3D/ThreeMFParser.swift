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

struct NamedMesh: Sendable {
    let name: String
    let mesh: TriangleMesh
}

struct LoadedModel: Sendable {
    let mesh: TriangleMesh
    let parts: [NamedMesh]
}

enum ThreeMFParser {
    static func parse(_ url: URL) throws -> LoadedModel {
        let document = ThreeMFDocument()
        let parser = XMLParser(data: try modelData(from: url))
        parser.delegate = document
        guard parser.parse() else { throw ThreeMFError.unreadable }
        let parts = document.parts()
        var mesh = TriangleMesh()
        for part in parts {
            mesh.append(part.mesh)
        }
        guard mesh.triangleCount > 0 else { throw ThreeMFError.empty }
        return LoadedModel(mesh: mesh, parts: parts)
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
        let name: String?
        let material: MaterialReference?
    }

    private var millimetersPerUnit: Float = 1
    private var materialGroups: [String: [SIMD4<Float>]] = [:]
    private var objects: [String: MeshObject] = [:]
    private var buildItems: [Placement] = []
    private var currentGroupID: String?
    private var currentObjectID: String?
    private var currentObject: MeshObject?

    func parts() -> [NamedMesh] {
        let roots = buildItems.isEmpty
            ? objects.keys.sorted().map { Placement(objectID: $0, transform: matrix_identity_float4x4) }
            : buildItems
        return roots.enumerated().map { index, root in
            var mesh = TriangleMesh()
            append(root.objectID, transform: root.transform, to: &mesh, depth: 0)
            return NamedMesh(name: name(of: root.objectID, depth: 0) ?? "part \(index + 1)", mesh: mesh)
        }
    }

    private func name(of objectID: String, depth: Int) -> String? {
        guard depth < 16, let object = objects[objectID] else { return nil }
        if let name = object.name, !name.isEmpty {
            return name
        }
        return object.components.lazy.compactMap { self.name(of: $0.objectID, depth: depth + 1) }.first
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
