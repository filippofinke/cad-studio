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

    func state(at time: Double) -> State {
        guard let first = frames.first else {
            return State(poses: [:], label: nil, values: [], collisions: [])
        }
        let upper = frames.firstIndex { $0.t >= time } ?? frames.count - 1
        let next = frames[upper]
        let previous = upper > 0 ? frames[upper - 1] : first
        let span = next.t - previous.t
        let fraction = Float(span > 0 ? min(max((time - previous.t) / span, 0), 1) : 1)
        let names = Set(previous.parts.keys).union(next.parts.keys)
        var poses: [String: Pose] = [:]
        for name in names {
            let start = previous.parts[name] ?? next.parts[name] ?? .identity
            let end = next.parts[name] ?? start
            poses[name] = start.interpolated(to: end, fraction: fraction)
        }
        let values = valueNames.compactMap { name -> (name: String, value: Double)? in
            guard let start = previous.values[name] ?? next.values[name] else { return nil }
            let end = next.values[name] ?? start
            return (name, start + (end - start) * Double(fraction))
        }
        let nearest = fraction < 0.5 ? previous : next
        let label = frames.last { $0.t <= time && $0.label != nil }?.label
        return State(poses: poses, label: label, values: values, collisions: nearest.collisions)
    }

    private enum CodingKeys: String, CodingKey {
        case title, frames
    }
}
