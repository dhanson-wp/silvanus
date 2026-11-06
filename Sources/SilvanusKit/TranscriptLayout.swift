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

extension TranscriptLayout {
    /// The link scheme of a word in a paragraph: `silvanus-word:<index>`.
    public static let linkScheme = "silvanus-word"

    /// A block's paragraph: each word and the space after it is one link to the word's index
    /// in the whole transcript (`firstWord + i`), so a click anywhere up to the next word
    /// picks that word. `style` styles the word itself (not its space), given its index.
    public static func paragraph(_ block: Block,
                                 style: (Int, Word, inout AttributedString) -> Void = { _, _, _ in }) -> AttributedString {
        var out = AttributedString()
        for (i, word) in block.words.enumerated() {
            let index = block.firstWord + i
            let link = URL(string: "\(linkScheme):\(index)")
            var run = AttributedString(word.text)
            style(index, word, &run)
            run.link = link
            out.append(run)
            if i < block.words.count - 1 {
                var space = AttributedString(" ")
                space.link = link
                out.append(space)
            }
        }
        return out
    }

    /// The word index in a paragraph's link, or nil for any other link.
    public static func wordIndex(link url: URL) -> Int? {
        guard url.scheme == linkScheme else { return nil }
        return Int(url.absoluteString.dropFirst(linkScheme.count + 1))
    }
}

/// The names the transcript shows for its two sides.
public enum SpeakerNames {
    /// The meeting's own names win (`speakers["me"]`, `speakers["them"]`, when not blank);
    /// otherwise `defaultMe` and "Them".
    public static func resolve(info: MeetingInfo, defaultMe: String) -> (me: String, them: String) {
        func name(_ key: Side) -> String? {
            let value = info.speakers[key.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        return (name(.me) ?? defaultMe, name(.them) ?? "Them")
    }
}
