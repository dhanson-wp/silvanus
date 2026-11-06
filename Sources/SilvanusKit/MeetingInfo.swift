import Foundation

/// How a meeting was transcribed.
public struct ASRInfo: Codable, Equatable, Sendable {
    public var engine: String
    public var model: String
    public var processedAt: Date

    public init(engine: String, model: String, processedAt: Date) {
        self.engine = engine
        self.model = model
        self.processedAt = processedAt
    }

    enum CodingKeys: String, CodingKey {
        case engine, model
        case processedAt = "processed_at"
    }
}

/// The body of `meeting.json`: everything about a meeting that isn't prose.
public struct MeetingInfo: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// The recurring series this meeting belongs to. Names the folder on disk.
    /// Empty means "use the title".
    public var series: String
    public var start: Date
    public var end: Date?
    public var attendees: [String]
    /// The sidebar folder the person filed it in (not the folder on disk).
    public var folder: String?
    /// "silvanus" for meetings recorded here, "granola" for imported ones.
    public var source: String
    public var granolaID: String?
    /// The UUID in a Granola note's web link; ties an API note to its gap note.
    public var granolaUUID: String?
    /// Speaker key to display name.
    public var speakers: [String: String]
    public var asr: ASRInfo?

    public init(id: String = UUID().uuidString.lowercased(), title: String, series: String = "",
                start: Date, end: Date? = nil, attendees: [String] = [], folder: String? = nil,
                source: String = "silvanus", granolaID: String? = nil, granolaUUID: String? = nil,
                speakers: [String: String] = [:], asr: ASRInfo? = nil) {
        self.id = id
        self.title = title
        self.series = series
        self.start = start
        self.end = end
        self.attendees = attendees
        self.folder = folder
        self.source = source
        self.granolaID = granolaID
        self.granolaUUID = granolaUUID
        self.speakers = speakers
        self.asr = asr
    }

    enum CodingKeys: String, CodingKey {
        case id, title, series, start, end, attendees, folder, source, speakers, asr
        case granolaID = "granola_id"
        case granolaUUID = "granola_uuid"
    }

    static func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    static func decoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
}
