import Foundation

struct Manifest: Decodable {
    struct BoundingBox: Decodable {
        let x: Double
        let y: Double
        let z: Double
    }

    let boundingBox: BoundingBox?
    let warnings: [String]
    let parameters: [String: Double]

    enum CodingKeys: String, CodingKey {
        case boundingBox = "bounding_box"
        case warnings
        case parameters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        boundingBox = try? container.decode(BoundingBox.self, forKey: .boundingBox)
        warnings = (try? container.decode([String].self, forKey: .warnings)) ?? []
        let values = (try? container.decode([String: JSONValue].self, forKey: .parameters)) ?? [:]
        parameters = values.compactMapValues { value in
            if case .number(let number) = value { number } else { nil }
        }
    }
}
