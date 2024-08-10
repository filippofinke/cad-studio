import Foundation

@MainActor
@Observable
final class MotionPlayer {
    var time = 0.0
    var isPlaying = false
    var speed = 1.0
    var loops = true

    func advance(by seconds: Double, duration: Double) {
        guard isPlaying, duration > 0 else { return }
        let next = time + seconds * speed
        if next < duration {
            time = next
        } else if loops {
            time = next.truncatingRemainder(dividingBy: duration)
        } else {
            time = duration
            isPlaying = false
        }
    }

    func togglePlayback(duration: Double) {
        if !isPlaying, time >= duration {
            time = 0
        }
        isPlaying.toggle()
    }
}
