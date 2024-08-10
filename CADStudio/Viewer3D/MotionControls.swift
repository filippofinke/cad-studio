import SwiftUI

struct MotionControls: View {
    let player: MotionPlayer
    let study: MotionStudy

    private static let speeds: [Double] = [0.1, 0.25, 0.5, 1, 2]

    var body: some View {
        let state = study.state(at: player.time)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    player.togglePlayback(duration: study.duration)
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 16)
                }
                .keyboardShortcut(.space, modifiers: [])
                .help(player.isPlaying ? "Pausa" : "Riproduci")
                Slider(
                    value: Binding(get: { player.time }, set: { player.time = $0 }),
                    in: 0...max(study.duration, 0.001),
                    onEditingChanged: { editing in
                        if editing {
                            player.isPlaying = false
                        }
                    }
                )
                .accessibilityLabel(Text("Tempo dell’animazione"))
                Text("\(player.time.formatted(.number.precision(.fractionLength(2)))) / \(study.duration.formatted(.number.precision(.fractionLength(2)))) s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Menu {
                    Picker("Velocità", selection: Binding(get: { player.speed }, set: { player.speed = $0 })) {
                        ForEach(Self.speeds, id: \.self) { speed in
                            Text("\(speed.formatted())×").tag(speed)
                        }
                    }
                    .pickerStyle(.inline)
                    Toggle("Ripeti", isOn: Binding(get: { player.loops }, set: { player.loops = $0 }))
                } label: {
                    Text("\(player.speed.formatted())×")
                        .font(.caption.monospacedDigit())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Velocità di riproduzione")
            }
            if state.label != nil || !state.values.isEmpty || !state.collisions.isEmpty {
                HStack(spacing: 12) {
                    if let label = state.label {
                        Text(label)
                            .fontWeight(.medium)
                    }
                    ForEach(state.values, id: \.name) { item in
                        Text("\(item.name) \(item.value.formatted(.number.precision(.significantDigits(1...3))))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    if !state.collisions.isEmpty {
                        Label(collisionText(state.collisions), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
            }
        }
        .controlSize(.small)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(10)
    }

    private func collisionText(_ collisions: [MotionStudy.Collision]) -> String {
        collisions
            .map { collision in
                let pair = collision.parts.joined(separator: " ↔ ")
                guard let volume = collision.volume else { return pair }
                return "\(pair) \(volume.formatted(.number.precision(.significantDigits(1...2)))) mm³"
            }
            .joined(separator: ", ")
    }
}
