import Foundation
import simd

enum STLError: LocalizedError {
    case unreadable
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "Il file STL non è leggibile.")
        case .empty: String(localized: "Il file STL non contiene triangoli.")
        }
    }
}

enum STLParser {
    static func parse(_ url: URL) throws -> TriangleMesh {
        let data = try Data(contentsOf: url)
        let mesh = isBinary(data) ? parseBinary(data) : try parseASCII(data)
        guard mesh.triangleCount > 0 else { throw STLError.empty }
        return mesh
    }

    private static func isBinary(_ data: Data) -> Bool {
        guard data.count >= 84 else { return false }
        let count = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self).littleEndian }
        return data.count == 84 + 50 * Int(count)
    }

    private static func parseBinary(_ data: Data) -> TriangleMesh {
        var mesh = TriangleMesh()
        data.withUnsafeBytes { bytes in
            let count = Int(bytes.loadUnaligned(fromByteOffset: 80, as: UInt32.self).littleEndian)
            mesh.positions.reserveCapacity(count * 3)
            mesh.normals.reserveCapacity(count * 3)
            for index in 0..<count {
                let offset = 84 + index * 50 + 12
                func vertex(_ number: Int) -> SIMD3<Float> {
                    let start = offset + number * 12
                    return SIMD3(
                        Float(bitPattern: bytes.loadUnaligned(fromByteOffset: start, as: UInt32.self).littleEndian),
                        Float(bitPattern: bytes.loadUnaligned(fromByteOffset: start + 4, as: UInt32.self).littleEndian),
                        Float(bitPattern: bytes.loadUnaligned(fromByteOffset: start + 8, as: UInt32.self).littleEndian)
                    )
                }
                mesh.addTriangle(vertex(0), vertex(1), vertex(2))
            }
        }
        return mesh
    }

    private static func parseASCII(_ data: Data) throws -> TriangleMesh {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw STLError.unreadable
        }
        var mesh = TriangleMesh()
        var vertices: [SIMD3<Float>] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.first == "vertex", parts.count >= 4,
                  let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3])
            else { continue }
            vertices.append(SIMD3(x, y, z))
            if vertices.count == 3 {
                mesh.addTriangle(vertices[0], vertices[1], vertices[2])
                vertices.removeAll(keepingCapacity: true)
            }
        }
        return mesh
    }
}
