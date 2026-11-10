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

/// Removes the call's audio from the mic side before lines are built. A headset or
/// speakers leak the call into the microphone, and the speech model writes those
/// words down as if I'd said them. Two passes, each working on single words:
///
/// 1. `gate`: the leak is always quieter in the mic than in the call by about the
///    same amount (`leak`, measured from this recording). A mic word spoken while
///    the call is talking, and no louder than the leak plus a margin, is bleed.
/// 2. `dedupe`: what's left of the bleed still says what the call says. A mic word
///    the call also says within 2 seconds, in a run of such words, is bleed.
///
/// Nothing is thrown away: `TranscriptBuilder.build` keeps what both remove in
/// `Transcript.removedEcho`.
public enum EchoCleanup {
    /// The call counts as talking above this level.
    static let callFloor: Float = -45
    /// How far above the leak a mic word has to be to count as my voice.
    static let margin: Float = 8
    /// Call audio needed to measure the leak: 5 seconds of frames.
    static let leakFrames = 250

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
