import Foundation

/// How the Transcript view groups a transcript: one block per turn, under one speaker label.
public enum TranscriptLayout {
    /// Words below this confidence get the dotted underline.
    public static let lowConfidence: Float = 0.6

    /// One speaker's turn: consecutive lines from one side, merged under one label.
    public struct Block: Equatable, Identifiable, Sendable {
        /// The block's place in the transcript, from 0.
        public var id: Int
        public var side: Side
        public var speaker: String
        public var words: [Word]
        /// Where this block's first word sits among every word of the transcript, so a
        /// word is named by one number across blocks.
        public var firstWord: Int

        public var start: TimeInterval { words.first?.start ?? 0 }
        public var text: String { words.map(\.text).joined(separator: " ") }
    }

    /// The transcript's turns. `me` and `them` are the names shown for the two sides.
    /// Lines with no words are skipped.
    public static func blocks(_ t: Transcript, me: String, them: String = "Them") -> [Block] {
        var blocks: [Block] = []
        var count = 0
        for line in t.lines where !line.words.isEmpty {
            if let last = blocks.last, last.side == line.side {
                blocks[blocks.count - 1].words += line.words
            } else {
                blocks.append(Block(id: blocks.count, side: line.side, speaker: line.side == .me ? me : them,
                                    words: line.words, firstWord: count))
            }
            count += line.words.count
        }
        return blocks
    }

    /// Every word in the blocks, in order: index `firstWord + i` is a block's word `i`.
    public static func words(_ blocks: [Block]) -> [Word] {
        blocks.flatMap(\.words)
    }

    public static func isLowConfidence(_ word: Word) -> Bool {
        word.confidence < lowConfidence
    }

    /// The transcript's length: where its last word ends.
    public static func duration(_ t: Transcript) -> TimeInterval {
        t.lines.reduce(0) { max($0, $1.end) }
    }
}

extension TranscriptLayout {
    /// The word being said at `time`: the last word that starts at or before it. Nil before
    /// the first word. The words must be sorted by start (as `words(_:)` returns them).
    public static func wordIndex(at time: TimeInterval, in words: [Word]) -> Int? {
        var low = 0, high = words.count
        while low < high {
            let mid = (low + high) / 2
            if words[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }

    /// How much speech each of `slices` equal slices of the transcript holds, from 0 (none)
    /// to 1 (words the whole time). The player strip draws it until audio levels are wired.
    public static func activity(_ t: Transcript, slices: Int) -> [Double] {
        guard slices > 0 else { return [] }
        var levels = [Double](repeating: 0, count: slices)
        let length = duration(t)
        guard length > 0 else { return levels }
        let slice = length / Double(slices)
        for line in t.lines {
            for word in line.words where word.end > word.start {
                var i = max(0, min(slices - 1, Int(word.start / slice)))
                while i < slices {
                    let from = Double(i) * slice, to = from + slice
                    let covered = min(word.end, to) - max(word.start, from)
                    if covered > 0 { levels[i] += covered / slice }
                    if word.end <= to { break }
                    i += 1
                }
            }
        }
        return levels.map { min(1, $0) }
    }
}
