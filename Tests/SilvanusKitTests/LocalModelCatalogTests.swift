import Foundation
import Testing
@testable import SilvanusKit

@Suite("Local model catalog") struct LocalModelCatalogTests {
    @Test("There are two models, each pinned to a commit with its size and checksum")
    func twoPinnedModels() {
        #expect(LocalModelCatalog.all.map(\.name) == ["Gemma 4, 12B", "Gemma 4, small"])
        for model in LocalModelCatalog.all {
            #expect(model.url.host == "huggingface.co")
            #expect(model.url.scheme == "https")
            #expect(!model.url.path.contains("/resolve/main/"))
            #expect(model.url.path.range(of: #"/resolve/[0-9a-f]{40}/"#, options: .regularExpression) != nil)
            #expect(model.sha256.count == 64)
            #expect(model.fileName.hasSuffix(".gguf"))
            #expect(model.partialName == model.fileName + ".download")
        }
        #expect(LocalModelCatalog.large.bytes == 7_366_423_360)
        #expect(LocalModelCatalog.small.bytes == 2_620_370_976)
        #expect(LocalModelCatalog.large.fileName == "gemma-4-12b-it-UD-Q4_K_XL.gguf")
        #expect(LocalModelCatalog.small.fileName == "gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf")
    }

    @Test("A Mac with 24 GB of memory or more gets the 12B model; less gets the small one")
    func recommendedFollowsMemory() {
        #expect(LocalModelCatalog.recommended(physicalMemory: 8 << 30)?.id == "small")
        #expect(LocalModelCatalog.recommended(physicalMemory: 16 << 30)?.id == "small")
        #expect(LocalModelCatalog.recommended(physicalMemory: 23_999_999_999)?.id == "small")
        #expect(LocalModelCatalog.recommended(physicalMemory: 24_000_000_000)?.id == "12b")
        #expect(LocalModelCatalog.recommended(physicalMemory: 24 << 30)?.id == "12b")
        #expect(LocalModelCatalog.recommended(physicalMemory: 64 << 30)?.id == "12b")
        #expect(LocalModelCatalog.ordered(physicalMemory: 8 << 30).map(\.id) == ["small", "12b"])
        #expect(LocalModelCatalog.ordered(physicalMemory: 32 << 30).map(\.id) == ["12b", "small"])
    }

    @Test("Sizes and progress read in plain units")
    func sizes() {
        #expect(LocalModelCatalog.size(7_366_423_360) == "7.4 GB")
        #expect(LocalModelCatalog.size(2_620_370_976) == "2.6 GB")
        #expect(LocalModelCatalog.size(450_000_000) == "450 MB")
        #expect(LocalModelCatalog.size(4_096) == "4 KB")
        #expect(LocalModelCatalog.progress(2_100_000_000, of: 7_366_423_360) == "2.1 of 7.4 GB")
        #expect(LocalModelCatalog.progress(0, of: 2_620_370_976) == "0.0 of 2.6 GB")
        #expect(LocalModelCatalog.progress(9_000_000_000, of: 7_366_423_360) == "7.4 of 7.4 GB")
        #expect(LocalModelCatalog.progress(2_000, of: 4_096) == "2 of 4 KB")
    }

    @Test("A download picks up where the partial file ends")
    func resume() {
        #expect(ModelDownloadRules.resumeOffset(partialBytes: 0, total: 100) == 0)
        #expect(ModelDownloadRules.resumeOffset(partialBytes: 40, total: 100) == 40)
        #expect(ModelDownloadRules.resumeOffset(partialBytes: 100, total: 100) == 100)
        #expect(ModelDownloadRules.resumeOffset(partialBytes: 140, total: 100) == 0)
        #expect(ModelDownloadRules.rangeHeader(offset: 0) == nil)
        #expect(ModelDownloadRules.rangeHeader(offset: 40) == "bytes=40-")
    }

    @Test("The server's answer says whether to add to the partial file or start over")
    func start() {
        #expect(ModelDownloadRules.start(status: 200, offset: 0, contentRange: nil) == .restart)
        #expect(ModelDownloadRules.start(status: 200, offset: 40, contentRange: nil) == .restart)
        #expect(ModelDownloadRules.start(status: 206, offset: 40, contentRange: "bytes 40-99/100") == .append)
        #expect(ModelDownloadRules.start(status: 206, offset: 40, contentRange: "bytes 0-99/100") == .discard)
        #expect(ModelDownloadRules.start(status: 206, offset: 40, contentRange: nil) == .discard)
        #expect(ModelDownloadRules.start(status: 416, offset: 40, contentRange: nil) == .discard)
        #expect(ModelDownloadRules.start(status: 404, offset: 0, contentRange: nil) == .refuse(404))
        #expect(ModelDownloadRules.start(status: 503, offset: 40, contentRange: nil) == .refuse(503))
    }

    @Test("A download is refused when the disk has no room for the rest and some to spare")
    func room() {
        let total: Int64 = 7_366_423_360
        #expect(ModelDownloadRules.noRoom(total: total, partialBytes: 0, free: 20_000_000_000) == nil)
        #expect(ModelDownloadRules.noRoom(total: total, partialBytes: 0, free: nil) == nil)
        #expect(ModelDownloadRules.noRoom(total: total, partialBytes: 0, free: 3_200_000_000)
            == "Not enough disk space. This needs 7.9 GB free, and there's 3.2 GB.")
        // What's already downloaded doesn't count against the room.
        #expect(ModelDownloadRules.noRoom(total: total, partialBytes: 5_000_000_000, free: 3_200_000_000) == nil)
    }

    @Test("A file's checksum is read in chunks")
    func checksum() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("silvanus-hash-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        #expect(ModelDownloadRules.sha256(of: file) == abc)
        #expect(ModelDownloadRules.sha256(of: file, chunk: 1) == abc)
        #expect(ModelDownloadRules.sha256(of: file, keepGoing: { false }) == nil)
        #expect(ModelDownloadRules.sha256(of: file.appendingPathExtension("gone")) == nil)
    }
}
