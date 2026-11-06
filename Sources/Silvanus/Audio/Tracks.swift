import Foundation
import SilvanusKit

/// `audio/tracks.json` in a meeting's folder: when each track's first sample
/// landed, measured from the recording's start, and how long it ran.
nonisolated struct Tracks: Codable, Equatable, Sendable {
    nonisolated struct Track: Codable, Equatable, Sendable {
        var startOffset: TimeInterval
        var seconds: TimeInterval
        init(startOffset: TimeInterval, seconds: TimeInterval) { self.startOffset = startOffset; self.seconds = seconds }
        init(_ w: SegmentWriter) {
            startOffset = w.startOffset ?? 0
            seconds = Double(w.framesWritten) / TrackFormat.sampleRate
        }
    }
    var mic: Track?
    var system: Track?

    static let fileName = "tracks.json"

    func save(in dir: URL) throws {
        try JSONEncoder().encode(self).write(to: dir.appending(path: Self.fileName), options: .atomic)
    }

    /// The saved tracks, or both tracks starting at zero when `tracks.json` is missing
    /// or unreadable (a recording cut off by a quit or crash).
    static func load(from dir: URL) -> Tracks {
        (try? JSONDecoder().decode(Tracks.self, from: Data(contentsOf: dir.appending(path: fileName))))
            ?? Tracks(mic: Track(startOffset: 0, seconds: 0), system: Track(startOffset: 0, seconds: 0))
    }
}
