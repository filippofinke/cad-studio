import Foundation
import simd

struct MotionStudy: Decodable, Sendable {
    struct Pose: Decodable, Sendable {
        let translate: SIMD3<Float>
        let rotate: simd_quatf

        static let identity = Pose(translate: .zero, rotate: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))

        init(translate: SIMD3<Float>, rotate: simd_quatf) {
            self.translate = translate
            self.rotate = rotate
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let offset = (try? container.decode([Float].self, forKey: .translate)) ?? []
            let rotation = (try? container.decode([Float].self, forKey: .rotate)) ?? []
            translate = offset.count == 3 ? SIMD3(offset[0], offset[1], offset[2]) : .zero
            rotate = rotation.count == 4
                ? simd_normalize(simd_quatf(ix: rotation[0], iy: rotation[1], iz: rotation[2], r: rotation[3]))
                : Pose.identity.rotate
        }

        func interpolated(to other: Pose, fraction: Float) -> Pose {
            Pose(
                translate: simd_mix(translate, other.translate, SIMD3(repeating: fraction)),
                rotate: simd_slerp(rotate, other.rotate, fraction)
            )
        }

        private enum CodingKeys: String, CodingKey {
            case translate, rotate
        }
    }

    struct Collision: Decodable, Sendable, Hashable {
        let parts: [String]
        let volume: Double?
    }

    struct Frame: Decodable, Sendable {
        let t: Double
        let label: String?
        let parts: [String: Pose]
        let values: [String: Double]
        let collisions: [Collision]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            t = try container.decode(Double.self, forKey: .t)
            label = try? container.decode(String.self, forKey: .label)
            parts = (try? container.decode([String: Pose].self, forKey: .parts)) ?? [:]
            values = (try? container.decode([String: Double].self, forKey: .values)) ?? [:]
            collisions = (try? container.decode([Collision].self, forKey: .collisions)) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case t, label, parts, values, collisions
        }
    }

    struct State {
        let poses: [String: Pose]
        let label: String?
        let values: [(name: String, value: Double)]
        let collisions: [Collision]

        var collidingParts: Set<String> {
            Set(collisions.flatMap(\.parts))
        }
    }

    let title: String?
    let frames: [Frame]
    let valueNames: [String]

    var duration: Double { frames.last?.t ?? 0 }

    var movingParts: Set<String> {
        Set(frames.flatMap(\.parts.keys))
    }

    var collisionCount: Int {
        frames.filter { !$0.collisions.isEmpty }.count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try? container.decode(String.self, forKey: .title)
        frames = try container.decode([Frame].self, forKey: .frames).sorted { $0.t < $1.t }
        var names: [String] = []
        for frame in frames {
            for name in frame.values.keys.sorted() where !names.contains(name) {
                names.append(name)
            }
        }
        valueNames = names
    }
