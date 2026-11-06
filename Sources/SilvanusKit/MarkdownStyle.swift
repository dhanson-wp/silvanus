/// Reads the Markdown the notes editor styles: block markers at the start of a
/// line, and bold, italic, and code inside it. It never changes the text; the
/// editor turns these ranges into attributes, so the file stays plain Markdown.
///
/// Every range counts UTF-16 code units from the start of the line (or of the
/// text, for `runs`), the same units NSTextView and NSRange use.
public enum MarkdownStyle {
    public enum BlockKind: Equatable, Sendable {
        case heading(level: Int)
        case bullet
        case numbered
        case task(done: Bool)
        case quote
        case paragraph
    }

    public struct Block: Equatable, Sendable {
        public var kind: BlockKind
        /// Leading tabs and spaces before the marker.
        public var indent: Range<Int>
        /// The marker with its trailing space ("# ", "- ", "1. ", "[ ] ", "- [ ] ", "> ").
        /// Empty for a paragraph.
        public var marker: Range<Int>
        /// For a task, the "[ ]" or "[x]" box inside the marker.
        public var box: Range<Int>?
        /// What follows the marker, up to the end of the line.
        public var content: Range<Int>
    }

    public enum InlineKind: Equatable, Sendable { case bold, italic, code }

    public struct InlineSpan: Equatable, Sendable {
        public var kind: InlineKind
        /// From the opening marker through the closing one.
        public var range: Range<Int>
        public var content: Range<Int>
        /// The opening and closing markers.
        public var markers: [Range<Int>]
    }

    /// What the editor does with a range.
    public enum Role: Equatable, Hashable, Sendable {
        /// Markdown syntax: dimmed when the caret is not on the line.
        case marker
        case heading(level: Int)
        case bold, italic, code
        case quote
        /// The content of a done task.
        case done
    }

    public struct Run: Equatable, Sendable {
        public var range: Range<Int>
        public var role: Role
    }

    // MARK: Blocks

    public static func blockKind(_ line: Substring) -> BlockKind { block(line).kind }

    public static func block(_ line: Substring) -> Block {
        let u = Array(line.utf16)
        let end = u.count
        var i = 0
        while i < end, u[i] == tab || u[i] == space { i += 1 }
        let indent = 0..<i
        func make(_ kind: BlockKind, markerEnd: Int, box: Range<Int>? = nil) -> Block {
            Block(kind: kind, indent: indent, marker: i..<markerEnd, box: box, content: markerEnd..<end)
        }
        // A space after the marker, or the end of the line (an empty item).
        func spaced(_ j: Int) -> Int? {
            if j == end { return j }
            return u[j] == space ? j + 1 : nil
        }
        // "[ ] " or "[x] " at j: returns the box range and where the marker ends.
        func taskBox(_ j: Int) -> (Range<Int>, Int, Bool)? {
            guard j + 2 < end, u[j] == openBracket, u[j + 2] == closeBracket,
                  let after = spaced(j + 3) else { return nil }
            switch u[j + 1] {
            case space: return (j..<(j + 3), after, false)
            case lowerX, upperX: return (j..<(j + 3), after, true)
            default: return nil
            }
        }
        guard i < end else { return make(.paragraph, markerEnd: i) }

        switch u[i] {
        case hash:
            var j = i
            while j < end, u[j] == hash { j += 1 }
            let level = j - i
            if level <= 6, j < end, u[j] == space { return make(.heading(level: level), markerEnd: j + 1) }
        case dash, star, plus:
            if let after = spaced(i + 1), i + 1 < end {
                if let (box, taskEnd, done) = taskBox(after) {
                    return make(.task(done: done), markerEnd: taskEnd, box: box)
                }
                return make(.bullet, markerEnd: after)
            }
        case openBracket:
            if let (box, taskEnd, done) = taskBox(i) {
                return make(.task(done: done), markerEnd: taskEnd, box: box)
            }
        case greater:
            if let after = spaced(i + 1) { return make(.quote, markerEnd: after) }
        case let c where isDigit(c):
            var j = i
            while j < end, isDigit(u[j]), j - i < 9 { j += 1 }
            if j < end, u[j] == dot || u[j] == closeParen, let after = spaced(j + 1) {
                return make(.numbered, markerEnd: after)
            }
        default: break
        }
        return Block(kind: .paragraph, indent: indent, marker: i..<i, box: nil, content: i..<end)
    }

    // MARK: Inline

    public static func inlineSpans(_ line: Substring) -> [InlineSpan] {
        spans(Array(line.utf16), from: 0, to: line.utf16.count)
    }

    private static func spans(_ u: [UInt16], from start: Int, to end: Int) -> [InlineSpan] {
        var out: [InlineSpan] = []
        var i = start
        while i < end {
            let c = u[i]
            if c == backtick, let close = find(backtick, in: u, from: i + 1, to: end), close > i + 1 {
                out.append(InlineSpan(kind: .code, range: i..<(close + 1), content: (i + 1)..<close,
                                      markers: [i..<(i + 1), close..<(close + 1)]))
                i = close + 1
                continue
            }
            if c == star, i + 1 < end, u[i + 1] == star,
               let close = findPair(star, in: u, from: i + 2, to: end), close > i + 2 {
                out.append(InlineSpan(kind: .bold, range: i..<(close + 2), content: (i + 2)..<close,
                                      markers: [i..<(i + 2), close..<(close + 2)]))
                out += spans(u, from: i + 2, to: close)
                i = close + 2
                continue
            }
            if (c == underscore || c == star), opensItalic(u, at: i, end: end),
               let close = closeItalic(c, in: u, from: i + 1, to: end) {
                out.append(InlineSpan(kind: .italic, range: i..<(close + 1), content: (i + 1)..<close,
                                      markers: [i..<(i + 1), close..<(close + 1)]))
                out += spans(u, from: i + 1, to: close)
                i = close + 1
                continue
            }
            i += 1
        }
        return out
    }

    private static func find(_ c: UInt16, in u: [UInt16], from: Int, to end: Int) -> Int? {
        var j = from
        while j < end { if u[j] == c { return j }; j += 1 }
        return nil
    }

    private static func findPair(_ c: UInt16, in u: [UInt16], from: Int, to end: Int) -> Int? {
        var j = from
        while j + 1 < end {
            if u[j] == backtick, let close = find(backtick, in: u, from: j + 1, to: end) { j = close + 1; continue }
            if u[j] == c, u[j + 1] == c { return j }
            j += 1
        }
        return nil
    }

    /// An italic marker opens when it is not inside a word and text follows it.
    private static func opensItalic(_ u: [UInt16], at i: Int, end: Int) -> Bool {
        guard i + 1 < end, u[i + 1] != space, u[i + 1] != u[i] else { return false }
        return i == 0 || !isWordChar(u[i - 1])
    }

    private static func closeItalic(_ c: UInt16, in u: [UInt16], from: Int, to end: Int) -> Int? {
        var j = from + 1
        while j < end {
            if u[j] == backtick, let close = find(backtick, in: u, from: j + 1, to: end) { j = close + 1; continue }
            if u[j] == c, u[j - 1] != space, j + 1 >= end || !isWordChar(u[j + 1]),
               c != star || j + 1 >= end || u[j + 1] != star {
                return j
            }
            j += 1
        }
        return nil
    }

    // MARK: Runs

    /// The styling runs for one line placed at `offset` in the text.
    public static func lineRuns(_ line: Substring, offset: Int) -> [Run] {
        let block = block(line)
        var runs: [Run] = []
        func add(_ r: Range<Int>, _ role: Role) {
            guard !r.isEmpty else { return }
            runs.append(Run(range: (r.lowerBound + offset)..<(r.upperBound + offset), role: role))
        }
        let whole = 0..<line.utf16.count
        switch block.kind {
        case .heading(let level): add(whole, .heading(level: level))
        case .quote: add(whole, .quote)
        case .task(done: true): add(block.content, .done)
        default: break
        }
        add(block.marker, .marker)
        // Inline spans only in the content, so "**" can't pair with a "*" bullet.
        let content = line.utf16.index(line.startIndex, offsetBy: block.content.lowerBound)
        let base = block.content.lowerBound
        for span in inlineSpans(line[content...]) {
            let role: Role = switch span.kind { case .bold: .bold; case .italic: .italic; case .code: .code }
            add((span.content.lowerBound + base)..<(span.content.upperBound + base), role)
            for m in span.markers { add((m.lowerBound + base)..<(m.upperBound + base), .marker) }
        }
        return runs
    }

    /// The styling runs for a whole text, line by line.
    public static func runs(in text: String) -> [Run] {
        var runs: [Run] = []
        var offset = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            runs += lineRuns(line, offset: offset)
            offset += line.utf16.count + 1
        }
        return runs
    }

    // MARK: Characters

    private static let tab: UInt16 = 9, space: UInt16 = 32, hash: UInt16 = 35, star: UInt16 = 42
    private static let plus: UInt16 = 43, dash: UInt16 = 45, dot: UInt16 = 46, closeParen: UInt16 = 41
    private static let greater: UInt16 = 62, openBracket: UInt16 = 91, closeBracket: UInt16 = 93
    private static let underscore: UInt16 = 95, backtick: UInt16 = 96, lowerX: UInt16 = 120, upperX: UInt16 = 88

    private static func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
    private static func isWordChar(_ c: UInt16) -> Bool {
        isDigit(c) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c > 127
    }
}
