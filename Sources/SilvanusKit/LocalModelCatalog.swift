import CryptoKit
import Foundation

/// A model Silvanus can download: where it is, how big it is, and how to tell the file
/// arrived whole.
public struct CatalogModel: Equatable, Sendable, Identifiable {
    /// A short stable name ("12b", "small"), for defaults and the headless download.
    public var id: String
    /// The name Settings shows.
    public var name: String
    /// Where to download it. Pinned to a commit, so the checksum can't drift.
    public var url: URL
    /// The file's size in bytes.
    public var bytes: Int64
    /// The file's SHA-256, in lowercase hex.
    public var sha256: String
    /// Roughly how much memory it uses while it writes, in GB.
    public var memoryGB: Int
    /// One line on which Macs it suits.
    public var bestFor: String

    public init(id: String, name: String, url: URL, bytes: Int64, sha256: String, memoryGB: Int, bestFor: String) {
        self.id = id
        self.name = name
        self.url = url
        self.bytes = bytes
        self.sha256 = sha256
        self.memoryGB = memoryGB
        self.bestFor = bestFor
    }

    /// The file's name in the models folder.
    public var fileName: String { url.lastPathComponent }
    /// The file's name while it downloads.
    public var partialName: String { fileName + ".download" }
}

/// The models Silvanus offers to download: Gemma 4 by Google (Apache 2.0), in GGUF
/// conversions by Unsloth. Sizes and checksums are the published ones.
public enum LocalModelCatalog {
    public static let large = CatalogModel(
        id: "12b", name: "Gemma 4, 12B",
        url: URL(string: "https://huggingface.co/unsloth/gemma-4-12b-it-GGUF/resolve/fc034cfff751157913579611efad8462ac1be606/gemma-4-12b-it-UD-Q4_K_XL.gguf")!,
        bytes: 7_366_423_360, sha256: "90fd944d227e9d9b68e7e2c7d5b57b79d4c66ed521b0919fbbd932cf834f6f8e",
        memoryGB: 8, bestFor: "Best for Macs with 24 GB of memory or more. Uses about 8 GB while it writes.")

    public static let small = CatalogModel(
        id: "small", name: "Gemma 4, small",
        url: URL(string: "https://huggingface.co/unsloth/gemma-4-E2B-it-qat-GGUF/resolve/66a399f68ddd113b06dff02fca9523e55465d11d/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf")!,
        bytes: 2_620_370_976, sha256: "e531007218dfab990486a5de7676a6932d6ea8dea233d1f698d7c21cf8a16889",
        memoryGB: 4, bestFor: "Best for Macs with less than 24 GB of memory. Uses about 4 GB while it writes.")

    /// Largest first.
    public static let all = [large, small]

    /// The license both models are under, and who made them.
    public static let licenseName = "Apache 2.0"
    public static let licenseURL = URL(string: "https://ai.google.dev/gemma/docs/gemma_4_license")!
    public static let credit = "Gemma 4 is made by Google, under the Apache 2.0 license. The files are GGUF conversions by Unsloth."

    /// A Mac with this much memory or more gets the large model.
    public static let largeModelMemory: UInt64 = 24_000_000_000

    /// The model to offer first on a Mac with `physicalMemory` bytes of memory.
    public static func recommended(physicalMemory: UInt64, from models: [CatalogModel] = all) -> CatalogModel? {
        guard let first = models.first else { return nil }
        return physicalMemory >= largeModelMemory ? first : models.last
    }

    /// `models` with the recommended one first.
    public static func ordered(physicalMemory: UInt64, from models: [CatalogModel] = all) -> [CatalogModel] {
        guard let best = recommended(physicalMemory: physicalMemory, from: models) else { return [] }
        return [best] + models.filter { $0.id != best.id }
    }

    /// "7.4 GB": a size in decimal units with one decimal, as Finder counts.
    public static func size(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 { return String(format: "%.1f GB", Double(bytes) / 1e9) }
        if bytes >= 1_000_000 { return String(format: "%.0f MB", Double(bytes) / 1e6) }
        return String(format: "%.0f KB", max(Double(bytes) / 1e3, bytes > 0 ? 1 : 0))
    }

    /// "2.1 of 7.4 GB": how far a download is, in the total's unit.
    public static func progress(_ done: Int64, of total: Int64) -> String {
        let whole = size(total)
        guard let unit = whole.split(separator: " ").last else { return whole }
        let divisor: Double = unit == "GB" ? 1e9 : unit == "MB" ? 1e6 : 1e3
        let format = unit == "GB" ? "%.1f" : "%.0f"
        return String(format: format, Double(min(max(done, 0), total)) / divisor) + " of " + whole
    }
}

/// The rules of a download that can stop and pick up again. Nothing here uses the network.
public enum ModelDownloadRules {
    /// Disk space kept free beyond the file itself.
    public static let spareBytes: Int64 = 500_000_000

    /// The bytes still to fetch, given what's already in the partial file. A partial file
    /// larger than the model is of no use, and starts over.
    public static func resumeOffset(partialBytes: Int64, total: Int64) -> Int64 {
        partialBytes > 0 && partialBytes <= total ? partialBytes : 0
    }

    /// The `Range` header that asks for the rest, or nil to ask for the whole file.
    public static func rangeHeader(offset: Int64) -> String? {
        offset > 0 ? "bytes=\(offset)-" : nil
    }

    /// What a server's answer means for the partial file.
    public enum Start: Equatable, Sendable {
        /// The rest follows: add it to the partial file.
        case append
        /// The whole file follows: start the partial file over.
        case restart
        /// The partial file can't be continued: delete it and ask again.
        case discard
        /// The server said no.
        case refuse(Int)
    }

    /// How to treat the answer to a request that asked to start at `offset`.
    /// `contentRange` is the answer's `Content-Range` header ("bytes 100-199/200").
    public static func start(status: Int, offset: Int64, contentRange: String?) -> Start {
        switch status {
        case 200: return .restart
        case 206:
            guard offset > 0 else { return .discard }
            guard let range = contentRange, let first = rangeStart(range) else { return .discard }
            return first == offset ? .append : .discard
        case 416: return .discard
        default: return .refuse(status)
        }
    }

    /// The first byte a `Content-Range` header covers.
    static func rangeStart(_ header: String) -> Int64? {
        let parts = header.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "/" })
        guard parts.count >= 2, parts[0].lowercased() == "bytes" else { return nil }
        return Int64(parts[1])
    }

    /// Nil when there's room for the rest of the file and some to spare; else what to say.
    public static func noRoom(total: Int64, partialBytes: Int64, free: Int64?) -> String? {
        guard let free else { return nil }
        let needed = max(total - partialBytes, 0) + spareBytes
        guard free < needed else { return nil }
        return "Not enough disk space. This needs \(LocalModelCatalog.size(needed)) free, and there's \(LocalModelCatalog.size(max(free, 0)))."
    }

    /// A file's SHA-256 in lowercase hex, read in chunks so a 7 GB file never sits in
    /// memory. `keepGoing` is asked between chunks; false stops and returns nil.
    public static func sha256(of file: URL, chunk: Int = 4 << 20, keepGoing: () -> Bool = { true }) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while keepGoing() {
            // Each chunk is released before the next is read.
            let more: Bool? = autoreleasepool {
                do {
                    // Nil at the end of the file.
                    let data = try handle.read(upToCount: chunk) ?? Data()
                    hasher.update(data: data)
                    return !data.isEmpty
                } catch {
                    return nil
                }
            }
            guard let more else { return nil }
            if !more { return hasher.finalize().map { String(format: "%02x", $0) }.joined() }
        }
        return nil
    }
}
