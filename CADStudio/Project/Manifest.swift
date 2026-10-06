import Foundation

struct Manifest: Decodable {
    struct BoundingBox: Decodable {
        let x: Double
        let y: Double
        let z: Double
    }

    struct Drawing: Decodable {
        let file: String
        let title: String
    }

    let boundingBox: BoundingBox?
    let warnings: [String]
    let parameters: [String: Double]
    let drawings: [Drawing]
    let bed: SIMD2<Float>?

    enum CodingKeys: String, CodingKey {
        case boundingBox = "bounding_box"
        case warnings
        case parameters
        case drawings
        case bed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        boundingBox = try? container.decode(BoundingBox.self, forKey: .boundingBox)
        warnings = (try? container.decode([String].self, forKey: .warnings)) ?? []
        let values = (try? container.decode([String: JSONValue].self, forKey: .parameters)) ?? [:]
        parameters = values.compactMapValues { value in
            if case .number(let number) = value { number } else { nil }
        }
        drawings = (try? container.decode([Drawing].self, forKey: .drawings)) ?? []
        let size = (try? container.decode([Float].self, forKey: .bed)) ?? []
        bed = size.count == 2 && size[0] > 0 && size[1] > 0 ? SIMD2(size[0], size[1]) : nil
    }
}
