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

    private mutating func materialIndex(for color: SIMD4<Float>) -> UInt32 {
        if let index = colors.firstIndex(of: color) {
            return UInt32(index + 1)
        }
        colors.append(color)
        return UInt32(colors.count)
    }
}

extension TriangleMesh {
    func color(ofTriangle index: Int) -> SIMD4<Float>? {
        let material = Int(faceMaterials[index])
        return material == 0 ? nil : colors[material - 1]
    }

    func clipped(axis: Int, at value: Float, keepsBelow: Bool) -> TriangleMesh {
        let sign: Float = keepsBelow ? 1 : -1
        var result = TriangleMesh()
        for index in 0..<triangleCount {
            let corners = Array(positions[index * 3..<index * 3 + 3])
            var polygon: [SIMD3<Float>] = []
            for (current, next) in zip(corners, corners[1...] + [corners[0]]) {
                let currentInside = sign * (current[axis] - value) <= 0
                let nextInside = sign * (next[axis] - value) <= 0
                if currentInside {
                    polygon.append(current)
                }
                if currentInside != nextInside {
                    let t = (value - current[axis]) / (next[axis] - current[axis])
                    polygon.append(current + (next - current) * t)
                }
            }
            guard polygon.count >= 3 else { continue }
            for corner in 1..<polygon.count - 1 {
                result.addTriangle(polygon[0], polygon[corner], polygon[corner + 1], color: color(ofTriangle: index))
            }
        }
        return result
    }

    func firstIntersection(origin: SIMD3<Float>, direction: SIMD3<Float>) -> SIMD3<Float>? {
        var nearest = Float.greatestFiniteMagnitude
        for index in 0..<triangleCount {
            let a = positions[index * 3]
            let edge1 = positions[index * 3 + 1] - a
            let edge2 = positions[index * 3 + 2] - a
            let p = simd_cross(direction, edge2)
            let determinant = simd_dot(edge1, p)
            guard abs(determinant) > 1e-9 else { continue }
            let inverse = 1 / determinant
            let offset = origin - a
            let u = simd_dot(offset, p) * inverse
            guard u >= 0, u <= 1 else { continue }
            let q = simd_cross(offset, edge1)
            let v = simd_dot(direction, q) * inverse
            guard v >= 0, u + v <= 1 else { continue }
            let t = simd_dot(edge2, q) * inverse
            if t > 0, t < nearest {
                nearest = t
            }
        }
        return nearest < .greatestFiniteMagnitude ? origin + direction * nearest : nil
    }
}
