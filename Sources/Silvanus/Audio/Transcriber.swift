import FluidAudio
import Foundation
import SilvanusKit

/// After-call speech to text with Parakeet TDT (English, v2) on the Neural
/// Engine through FluidAudio. The model downloads once (about 470 MB), then
/// everything runs offline.
actor Transcriber {
    static let shared = Transcriber()
    /// What `meeting.json`'s `asr` records.
    static let engine = "parakeet"
    static let model = "parakeet-tdt-0.6b-v2"
    /// What `transcript.json`'s `engine` records: the model and the library version.
    static let engineName = "\(model) (FluidAudio 0.13.5)"
    private let version: AsrModelVersion = .v2
    private var manager: AsrManager?

    var isModelDownloaded: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: version), version: version)
    }

    /// Loads the model, downloading it first if needed. `progress` gets 0…1 during a download.
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        if manager != nil { return }
        let dir = AsrModels.defaultCacheDirectory(for: version)
        let models: AsrModels
        if AsrModels.modelsExist(at: dir, version: version) {
            models = try await AsrModels.load(from: dir, version: version)
        } else {
            models = try await AsrModels.downloadAndLoad(to: dir, version: version) { p in progress(p.fractionCompleted) }
        }
        let asr = AsrManager(config: .default)
        try await asr.loadModels(models)
        manager = asr
    }

    /// Words with times in seconds from the start of the file.
    func words(in url: URL, source: AudioSource) async throws -> [Word] {
        guard let manager else { throw ASRError.notInitialized }
        let result = try await manager.transcribe(url, source: source)
        let tokens = (result.tokenTimings ?? []).map { (text: $0.token, start: $0.startTime, end: $0.endTime, confidence: $0.confidence) }
        if tokens.isEmpty, !result.text.isEmpty {
            // No timings came back: keep the text as one block at the start.
            return result.text.split(separator: " ").map { Word(text: String($0), start: 0, end: 0) }
        }
        return TranscriptBuilder.words(fromTokens: tokens)
    }
}
