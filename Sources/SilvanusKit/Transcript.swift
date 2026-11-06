import Foundation

/// Which side of the call a word came from. The mic track is me; the call
/// audio (system track) is them until speakers are named.
public enum Side: String, Codable, Sendable { case me, them }

public struct Word: Codable, Equatable, Sendable {
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var confidence: Float

    public init(text: String, start: TimeInterval, end: TimeInterval, confidence: Float = 1) {
        self.text = text; self.start = start; self.end = end; self.confidence = confidence
    }
}

/// One block of the transcript: consecutive words from one side.
public struct TranscriptLine: Codable, Equatable, Sendable, Identifiable {
    public var side: Side
    public var words: [Word]
    public var id: TimeInterval { start + (side == .me ? 0 : 0.0001) }
    public var start: TimeInterval { words.first?.start ?? 0 }
    public var end: TimeInterval { words.last?.end ?? 0 }
    public var text: String { words.map(\.text).joined(separator: " ") }

    public init(side: Side, words: [Word]) { self.side = side; self.words = words }
}

/// The sidecar JSON next to a meeting's Markdown: every word with its time
/// and confidence, plus what cleanup removed, so nothing is lost.
public struct Transcript: Codable, Equatable, Sendable {
    public var lines: [TranscriptLine]
    /// Mic lines dropped because they repeat the call audio (headset or speaker bleed).
    public var removedEcho: [TranscriptLine]
    public var engine: String
    public var processedAt: Date

    public init(lines: [TranscriptLine], removedEcho: [TranscriptLine] = [], engine: String, processedAt: Date = .now) {
        self.lines = lines; self.removedEcho = removedEcho; self.engine = engine; self.processedAt = processedAt
    }

    /// The `## Transcript` section: `[04:12] **Sam Rivera:** text`.
    public func markdown(me: String, them: String = "Them") -> String {
        lines.map { "[\(Clock.text($0.start))] **\($0.side == .me ? me : them):** \($0.text)" }
            .joined(separator: "\n\n")
    }
}

public enum TranscriptBuilder {
    /// Joins ASR word pieces into words. Pieces that start a word begin with
    /// "▁" or a space (SentencePiece); the rest continue the previous word.
    public static func words(fromTokens tokens: [(text: String, start: TimeInterval, end: TimeInterval, confidence: Float)],
                             offset: TimeInterval = 0) -> [Word] {
        var out: [Word] = []
        for t in tokens {
            let startsWord = t.text.hasPrefix("▁") || t.text.hasPrefix(" ")
            let piece = t.text.replacingOccurrences(of: "▁", with: "").trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { continue }
            let prev = out.last?.text.last
            // Digits and letters never share a word ("in" + "27" is two words), and a long gap starts a new one.
            let kindChange = prev.map { ($0.isLetter && piece.first!.isNumber) || ($0.isNumber && piece.first!.isLetter) } ?? false
            let gap = piece.first?.isPunctuation == false && out.last.map { $0.end < t.start - 0.3 } == true
            if startsWord || out.isEmpty || kindChange || gap {
                out.append(Word(text: piece, start: t.start + offset, end: t.end + offset, confidence: t.confidence))
            } else {
                out[out.count - 1].text += piece
                out[out.count - 1].end = t.end + offset
                out[out.count - 1].confidence = min(out[out.count - 1].confidence, t.confidence)
            }
        }
        return out
    }

    /// Groups one side's words into lines: a new line after a pause, or after
    /// a sentence ends once the line is long enough. The words must be sorted by start.
    public static func lines(_ words: [Word], side: Side, pause: TimeInterval = 1.2, maxLength: TimeInterval = 30) -> [TranscriptLine] {
        var lines: [TranscriptLine] = []
        var current: [Word] = []
        for w in words {
            if let last = current.last {
                let gap = w.start - last.end
                let sentenceDone = last.text.last.map { ".?!".contains($0) } ?? false
                let long = w.start - (current.first?.start ?? w.start)
                if gap > pause || long > maxLength || (sentenceDone && long > 12) {
                    lines.append(TranscriptLine(side: side, words: current)); current = []
                }
            }
            current.append(w)
        }
        if !current.isEmpty { lines.append(TranscriptLine(side: side, words: current)) }
        return lines
    }

    /// Decides whether a mic line is just the call audio leaking into the
    /// microphone. A mic line is dropped when at least `share` (half, by
    /// default) of its word pairs also appear in call lines within `window`
    /// seconds. A call line counts when it overlaps the span from `window`
    /// seconds before the mic line starts to `window` seconds after it ends.
    /// A line with fewer than two words has no pairs and is always kept.
    public static func isEcho(_ mic: TranscriptLine, them: [TranscriptLine], window: TimeInterval = 6, share: Double = 0.5) -> Bool {
        let micPairs = wordPairs(mic.words)
        guard !micPairs.isEmpty else { return false }
        let earliest = mic.start - window
        let latest = mic.end + window
        var callPairs = Set<String>()
        for call in them where call.end >= earliest && call.start <= latest {
            callPairs.formUnion(wordPairs(call.words))
        }
        let matching = micPairs.filter { callPairs.contains($0) }.count
        return Double(matching) >= share * Double(micPairs.count)
    }

    /// Both sides, with echo removed, in time order.
    public static func build(me: [Word], them: [Word], engine: String) -> Transcript {
        let themLines = lines(them, side: .them)
        let meLines = lines(me, side: .me)
        var kept: [TranscriptLine] = []
        var removed: [TranscriptLine] = []
        for line in meLines {
            if isEcho(line, them: themLines) { removed.append(line) } else { kept.append(line) }
        }
        // At equal start times my line comes first.
        let ordered = (kept + themLines).sorted {
            $0.start != $1.start ? $0.start < $1.start : ($0.side == .me && $1.side == .them)
        }
        return Transcript(lines: ordered, removedEcho: removed, engine: engine)
    }

    /// Lowercases a word and keeps only its letters, digits, and apostrophes.
    static func cleaned(_ word: String) -> String {
        String(word.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "'" })
    }

    /// Each pair of neighboring words, cleaned, as "first second". Words that
    /// clean down to nothing are skipped before pairing.
    static func wordPairs(_ words: [Word]) -> [String] {
        let kept = words.map { cleaned($0.text) }.filter { !$0.isEmpty }
        return zip(kept, kept.dropFirst()).map { "\($0) \($1)" }
    }
}
