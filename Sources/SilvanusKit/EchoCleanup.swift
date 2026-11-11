import Foundation

/// How loud each track is over time: one decibel value per 20 ms frame, both
/// tracks on the recording's clock. Silence is about -120.
public struct TrackLevels: Equatable, Sendable {
    public static let frame: TimeInterval = 0.02
    public var mic: [Float]
    public var call: [Float]

    public init(mic: [Float], call: [Float]) { self.mic = mic; self.call = call }

    /// One frame's level from its samples (-1…1).
    public static func decibels(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return -120 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return 20 * log10((sum / Float(samples.count)).squareRoot() + 1e-6)
    }
}

/// Removes the call's audio from the mic side. A headset or speakers leak the call
/// into the microphone, and the speech model writes those words down as if I'd said
/// them, however faint they are. First the audio: `bleedFrames` marks the stretches
/// of the mic track that hold only the leak, and the speech model never hears them
/// as my side. Then two passes over what it did hear, each working on single words:
///
/// 1. `gate`: the leak is always quieter in the mic than in the call by about the
///    same amount (`leak`, measured from this recording). A mic word spoken while
///    the call is talking, and no louder than the leak plus a margin, is bleed.
/// 2. `dedupe`: what's left of the bleed still says what the call says. A mic word
///    the call also says within 2 seconds, in a run of such words, is bleed.
///
/// Nothing is thrown away: `TranscriptBuilder.build` keeps what all three remove in
/// `Transcript.removedEcho`. Levels are measured on the speech band (`HighPass`), or
/// rumble in the mic drowns the leak.
public enum EchoCleanup {
    /// The call counts as talking above this level.
    static let callFloor: Float = -45
    /// How far above the leak a mic word has to be to count as my voice.
    static let margin: Float = 8
    /// Call audio needed to measure the leak: 5 seconds of frames.
    static let leakFrames = 250

    /// How far above the leak the mic has to be for its audio to count as my voice.
    static let voiceMargin: Float = 10
    /// A louder stretch shorter than this under the call is a click, not a word: 120 ms
    /// of smoothed frames, which one loud frame alone spreads to 100 ms.
    static let shortestVoice = 6
    /// Room kept around my voice: 60 ms before, 160 ms after.
    static let leadFrames = 3, tailFrames = 8

    /// Each frame's level averaged with its neighbors (`radius` each side), by power.
    static func smoothed(_ frames: [Float], radius: Int = 2) -> [Float] {
        let power = frames.map { pow(10, $0 / 10) }
        return frames.indices.map { index in
            let range = max(0, index - radius)...min(frames.count - 1, index + radius)
            return 10 * log10(power[range].reduce(0, +) / Float(range.count))
        }
    }

    /// The mic frames to silence before the speech model hears my side: true where
    /// the call is talking and the mic is no louder than the leak plus a margin.
    /// My voice keeps a little room before and after it; a click under the call
    /// goes with the leak. With no measurable leak, nothing is silenced.
    public static func bleedFrames(_ levels: TrackLevels) -> [Bool] {
        let count = min(levels.mic.count, levels.call.count)
        var mute = [Bool](repeating: false, count: levels.mic.count)
        let mic = smoothed(Array(levels.mic[..<count])), call = smoothed(Array(levels.call[..<count]))
        guard let leak = leak(TrackLevels(mic: mic, call: call)) else { return mute }
        var bleed = [Bool](repeating: false, count: count)
        for index in 0..<count {
            let near = call[max(0, index - 5)...min(count - 1, index + 5)].max() ?? -120
            bleed[index] = near > callFloor && mic[index] - near < leak + voiceMargin
        }
        // Stretches of voice between bleed: a short one is bleed too; the rest keep their room.
        var keep = [Bool](repeating: false, count: count)
        var index = 0
        while index < count {
            guard !bleed[index] else { index += 1; continue }
            var end = index
            while end < count, !bleed[end] { end += 1 }
            let click = end - index < shortestVoice && index > 0 && end < count
            if !click {
                for frame in max(0, index - leadFrames)..<min(count, end + tailFrames) { keep[frame] = true }
            }
            index = end
        }
        for frame in 0..<count { mute[frame] = !keep[frame] }
        return mute
    }

    /// How much quieter the call is in the mic track than in its own track, in
    /// decibels (negative): the median of mic minus call over the frames where the
    /// call is clearly talking. Nil when there's too little call audio to tell.
    public static func leak(_ levels: TrackLevels) -> Float? {
        var differences: [Float] = []
        for (mic, call) in zip(levels.mic, levels.call) where call > -40 && mic > -100 {
            differences.append(mic - call)
        }
        guard differences.count >= leakFrames else { return nil }
        differences.sort()
        return differences[differences.count / 2]
    }

    /// The average level from `start` to `end`, widened by `pad` on both sides.
    static func level(_ frames: [Float], from start: TimeInterval, to end: TimeInterval, pad: TimeInterval = 0) -> Float {
        let first = max(0, Int((start - pad) / TrackLevels.frame))
        let last = min(frames.count, Int(((end + pad) / TrackLevels.frame).rounded(.up)) + 1)
        guard first < last else { return -120 }
        var power: Float = 0
        for value in frames[first..<last] { power += pow(10, value / 10) }
        return 10 * log10(power / Float(last - first))
    }

    /// Splits mic words into mine and bleed by level. With no measurable leak, every word is kept.
    public static func gate(_ words: [Word], levels: TrackLevels) -> (kept: [Word], removed: [Word]) {
        guard let leak = leak(levels) else { return (words, []) }
        var kept: [Word] = [], removed: [Word] = []
        for word in words {
            let call = level(levels.call, from: word.start, to: word.end, pad: 0.1)
            let mic = level(levels.mic, from: word.start, to: word.end)
            if call > callFloor, mic - call < leak + margin { removed.append(word) } else { kept.append(word) }
        }
        return (kept, removed)
    }

    /// Splits mic words into mine and bleed by what the call says. A word matches
    /// when the call has the same word starting within `window` seconds. It's bleed
    /// when at least half of it and its neighbors (two each side, within 4 seconds)
    /// match, and either it matches itself or nearly all of them do. Both lists
    /// must be sorted by start.
    public static func dedupe(_ words: [Word], against call: [Word], window: TimeInterval = 2) -> (kept: [Word], removed: [Word]) {
        let callWords = call.map { (text: TranscriptBuilder.cleaned($0.text), start: $0.start) }
        var from = 0
        let matches: [Bool] = words.map { word in
            let text = TranscriptBuilder.cleaned(word.text)
            while from < callWords.count, callWords[from].start < word.start - window { from += 1 }
            guard !text.isEmpty else { return false }
            var index = from
            while index < callWords.count, callWords[index].start <= word.start + window {
                if callWords[index].text == text { return true }
                index += 1
            }
            return false
        }
        var kept: [Word] = [], removed: [Word] = []
        for (index, word) in words.enumerated() {
            let near = (max(0, index - 2)...min(words.count - 1, index + 2)).filter { abs(words[$0].start - word.start) < 4 }
            let matching = Double(near.filter { matches[$0] }.count)
            let total = Double(near.count)
            if matching >= 0.5 * total, matches[index] || matching >= 0.7 * total {
                removed.append(word)
            } else {
                kept.append(word)
            }
        }
        return (kept, removed)
    }

    /// Both passes. The second runs only when the first found real bleed (a tenth
    /// of the mic's words, and at least ten), so on a clean headset agreeing with
    /// someone in their own words is never mistaken for it.
    public static func clean(_ words: [Word], call: [Word], levels: TrackLevels) -> (kept: [Word], removed: [Word]) {
        let gated = gate(words, levels: levels)
        guard gated.removed.count >= max(10, words.count / 10) else { return gated }
        let deduped = dedupe(gated.kept, against: call)
        return (deduped.kept, (gated.removed + deduped.removed).sorted { $0.start < $1.start })
    }
}
