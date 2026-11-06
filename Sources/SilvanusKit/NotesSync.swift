import Foundation

/// The smallest edit that turns one text into another: everything before
/// `range` and after it is the same in both. Ranges count UTF-16 units, as
/// NSTextView does, and never split a surrogate pair.
public struct TextChange: Equatable, Sendable {
    /// The changed units in the old text.
    public var range: Range<Int>
    /// What replaces them.
    public var replacement: String

    public var isEmpty: Bool { range.isEmpty && replacement.isEmpty }

    /// The change from `old` to `new`: the common start and end are left out.
    public static func between(_ old: String, _ new: String) -> TextChange {
        let a = Array(old.utf16), b = Array(new.utf16)
        var prefix = 0
        let limit = min(a.count, b.count)
        while prefix < limit, a[prefix] == b[prefix] { prefix += 1 }
        // Never end the shared start on the first half of a pair.
        if prefix > 0, prefix < limit || prefix < max(a.count, b.count), UTF16.isLeadSurrogate(a[prefix - 1]) { prefix -= 1 }
        var suffix = 0
        while suffix < limit - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        // Never start the shared end on the second half of a pair.
        if suffix > 0, UTF16.isTrailSurrogate(a[a.count - suffix]) { suffix -= 1 }
        let inserted = Array(b[prefix..<(b.count - suffix)])
        return TextChange(range: prefix..<(a.count - suffix),
                          replacement: String(decoding: inserted, as: UTF16.self))
    }

    /// Where a caret at `location` in the old text belongs in the new one. Before the
    /// change it stays, after it it moves with the text, and inside it it goes to the
    /// end of what was put in.
    public func caret(_ location: Int) -> Int {
        let delta = replacement.utf16.count - range.count
        if location <= range.lowerBound { return location }
        if location >= range.upperBound { return location + delta }
        return range.lowerBound + replacement.utf16.count
    }
}

/// What the notes canvas knows about `notes.md` on disk: the text it last wrote or
/// read. A change on disk that equals that text is the canvas's own write; anything
/// else came from another app.
public struct NotesSync: Equatable, Sendable {
    /// The text in `notes.md` as of the last save or reload.
    public private(set) var lastSaved: String

    /// What to do about a change on disk.
    public enum Action: Equatable, Sendable {
        /// Nothing: our own write, an unreadable file, or the editor already shows it.
        case none
        /// Nothing unsaved in the editor: show the disk text.
        case show(String)
        /// Unsaved typing and the disk change touch different lines: show the merge, then save it.
        case merged(String)
        /// Both changed the same lines: keep the typing, keep `theirs` in a conflict copy, then save.
        case conflict(theirs: String)
    }

    public init(loaded: String) { lastSaved = loaded }

    /// The canvas wrote `text` to disk.
    public mutating func saved(_ text: String) { lastSaved = text }

    /// `notes.md` changed on disk (`nil` when it can't be read, as when it's missing:
    /// never mistaken for an empty note). `editorDirty` is true when the editor holds
    /// typing not yet saved.
    public mutating func diskChanged(to disk: String?, editor: String, editorDirty: Bool) -> Action {
        guard let disk, disk != lastSaved else { return .none }
        let base = lastSaved
        guard editorDirty else {
            lastSaved = disk
            return disk == editor ? .none : .show(disk)
        }
        let merge = TextMerge.threeWay(base: base, ours: editor, theirs: disk)
        // On a conflict `lastSaved` stays put: the other version isn't safe until its copy
        // is written, and the save that follows records ours.
        guard !merge.conflict else { return .conflict(theirs: disk) }
        lastSaved = disk
        return .merged(merge.merged)
    }
}

/// A line-based three-way merge. Each side's change from the base is taken as one
/// block of lines (from its first changed line to its last); when the two blocks
/// don't overlap both are applied, otherwise it's a conflict and `merged` is ours.
/// Coarse on purpose: two edits far apart on one side count as one block, so the
/// merge can call a conflict it could have resolved, but never drops a side's text.
/// A line that would end up joined to the next one (a block whose last line has no
/// newline, followed by the other side's lines) is a conflict too. Lines end at "\n"
/// or "\r\n" and keep their own ending, so CRLF and mixed files merge and keep their
/// style.
public enum TextMerge {
    public static func threeWay(base: String, ours: String, theirs: String) -> (merged: String, conflict: Bool) {
        if ours == theirs { return (ours, false) }
        if ours == base { return (theirs, false) }
        if theirs == base { return (ours, false) }
        let b = lines(base), o = lines(ours), t = lines(theirs)
        let a = block(b, o), c = block(b, t)
        let overlap = (a.range.lowerBound < c.range.upperBound && c.range.lowerBound < a.range.upperBound)
            || a.range.lowerBound == c.range.lowerBound
        guard !overlap else { return (ours, true) }
        // Apply the later block first, so the earlier one's line numbers still hold.
        var merged = b
        for edit in [a, c].sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            merged.replaceSubrange(edit.range, with: edit.lines)
        }
        // Every line but the last must still end its line, or two lines were glued.
        guard merged.dropLast().allSatisfy(endsLine) else { return (ours, true) }
        return (merged.joined(), false)
    }

    private static func endsLine(_ line: String) -> Bool {
        line.last == "\n" || line.last == "\r\n"
    }

    /// The lines of a text, each with its own ending, "\n" or "\r\n" (the last may have
    /// none). Swift reads "\r\n" as one Character, so both are checked.
    static func lines(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for c in text {
            current.append(c)
            if c == "\n" || c == "\r\n" { out.append(current); current = "" }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// The base lines a side replaced, and what it put there.
    private static func block(_ base: [String], _ side: [String]) -> (range: Range<Int>, lines: [String]) {
        var prefix = 0
        while prefix < base.count, prefix < side.count, base[prefix] == side[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < base.count - prefix, suffix < side.count - prefix,
              base[base.count - 1 - suffix] == side[side.count - 1 - suffix] { suffix += 1 }
        return (prefix..<(base.count - suffix), Array(side[prefix..<(side.count - suffix)]))
    }
}
