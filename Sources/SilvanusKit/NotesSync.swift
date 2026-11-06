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

    public init(loaded: String) { lastSaved = loaded }

    /// The canvas wrote `text` to disk.
    public mutating func saved(_ text: String) { lastSaved = text }

    /// `notes.md` changed on disk (`nil` when it can't be read). Returns the text to
    /// load into the editor, or nil to keep the editor as it is. Unsaved typing wins:
    /// it is written over the disk change at the next save.
    public mutating func diskChanged(to disk: String?, editor: String, editorDirty: Bool) -> String? {
        guard let disk, disk != lastSaved, !editorDirty else { return nil }
        lastSaved = disk
        return disk == editor ? nil : disk
    }
}
