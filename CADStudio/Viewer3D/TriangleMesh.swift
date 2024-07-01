import simd

struct TriangleMesh: Sendable {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var faceMaterials: [UInt32] = []
    var colors: [SIMD4<Float>] = []
    var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)

    var triangleCount: Int { positions.count / 3 }
    var size: SIMD3<Float> { triangleCount > 0 ? maximum - minimum : .zero }
    var center: SIMD3<Float> { (minimum + maximum) / 2 }

    mutating func addTriangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, color: SIMD4<Float>? = nil) {
        if let color {
            faceMaterials.append(materialIndex(for: color))
        } else {
            faceMaterials.append(0)
        }
        let cross = simd_cross(b - a, c - a)
        let length = simd_length(cross)
        let normal = length > 0 ? cross / length : SIMD3<Float>(0, 0, 1)
        for vertex in [a, b, c] {
            positions.append(vertex)
            normals.append(normal)
            minimum = simd_min(minimum, vertex)
            maximum = simd_max(maximum, vertex)
        }
    }

    mutating func append(_ other: TriangleMesh, offset: SIMD3<Float> = .zero) {
        for index in 0..<other.triangleCount {
            let base = index * 3
            addTriangle(
                other.positions[base] + offset,
                other.positions[base + 1] + offset,
                other.positions[base + 2] + offset,
                color: other.color(ofTriangle: index)
            )
        }
    }

    private mutating func materialIndex(for color: SIMD4<Float>) -> UInt32 {
        if let index = colors.firstIndex(of: color) {
            return UInt32(index + 1)
        }
        colors.append(color)
        return UInt32(colors.count)
    }
}
