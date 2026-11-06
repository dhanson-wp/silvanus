import Foundation

/// When each note line was written during a recording, in seconds from the recording's
/// start, kept beside the notes as `notes-times.json` ({line hash: seconds}) so the margin
/// timestamps survive a reload. The times live outside `notes.md`: the notes stay plain
/// Markdown.
///
/// A line keeps the time it first appeared: typing on, or editing it later, carries the
/// time to the new text; moving it keeps it. Only lines still in the note are kept, and
/// identical lines share one time (they share a hash).
public struct NoteTimes: Equatable, Sendable {
    public private(set) var byHash: [String: Double]

    public init(byHash: [String: Double] = [:]) {
        self.byHash = byHash
    }

    public var count: Int { byHash.count }
    public var isEmpty: Bool { byHash.isEmpty }

    /// The line's time, if it has one. Blank lines never do.
    public func time(for line: String) -> Double? {
        Self.isBlank(line) ? nil : byHash[Self.hash(line)]
    }

    /// The note changed from `old` to `new`. A line that replaced another at the same place
    /// takes its time; any other new line gets `now` (nil when not recording: no new times).
    public mutating func update(old: String, new: String, now: Double?) {
        let oldLines = Self.lines(old), newLines = Self.lines(new)
        // A moved line keeps its time by its own text; only a removal that wasn't a move can
        // hand its time to the line that took its place.
        let diff = newLines.difference(from: oldLines).inferringMoves()
        var removed: [Int: String] = [:]
        for change in diff {
            if case let .remove(offset, line, moved) = change, moved == nil { removed[offset] = line }
        }
        var next = byHash
        for change in diff {
            guard case let .insert(offset, line, _) = change, !Self.isBlank(line) else { continue }
            let key = Self.hash(line)
            if let replaced = removed[offset], let time = time(for: replaced) {
                next[key] = time
            } else if next[key] == nil, let now {
                next[key] = now
            }
        }
        let present = Set(newLines.filter { !Self.isBlank($0) }.map(Self.hash))
        byHash = next.filter { present.contains($0.key) }
    }

    /// A stable 64-bit FNV-1a hash of the line, as 16 hex digits. Swift's own hash values
    /// change from run to run, so they can't key a file.
    public static func hash(_ line: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in line.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", h)
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(byHash)
    }

    public init(json: Data) throws {
        byHash = try JSONDecoder().decode([String: Double].self, from: json)
    }

    private static func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }
}
