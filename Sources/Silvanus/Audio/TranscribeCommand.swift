import FluidAudio
import Foundation
import SilvanusKit

/// Headless transcription for agents, before any window opens.
///
///   APP_STORE=<dir> APP_TRANSCRIBE=<meeting id> Silvanus
/// runs the after-call pass on that meeting's `audio/` folder, writes its transcript,
/// prints it, and quits. APP_ME_NAME names the mic side (default "Me").
///
///   APP_TRANSCRIBE_FILE=<audio file> Silvanus
/// transcribes one file and prints each word with its start and end in seconds and its
/// confidence. Touches no meetings. Both load the speech model (downloading it the
/// first time) and never open the microphone or call audio.
enum TranscribeCommand {
    static func runIfRequested() -> Int32? {
        let env = ProcessInfo.processInfo.environment
        if let path = env["APP_TRANSCRIBE_FILE"], !path.isEmpty {
            setvbuf(stdout, nil, _IOLBF, 0)
            return wait { await transcribeFile(URL(fileURLWithPath: (path as NSString).expandingTildeInPath)) }
        }
        if let id = env["APP_TRANSCRIBE"], !id.isEmpty {
            setvbuf(stdout, nil, _IOLBF, 0)
            guard Store.isOverridden else {
                print("TRANSCRIBE refused: set APP_STORE")
                return 1
            }
            let me = env["APP_ME_NAME"].flatMap { $0.isEmpty ? nil : $0 } ?? AppDefaults.meName
            return wait { await transcribeMeeting(id, me: me) }
        }
        return nil
    }

    private static func transcribeFile(_ url: URL) async -> Int32 {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("TRANSCRIBE FAIL no file at \(url.lastPathComponent)")
            return 1
        }
        do {
            let clock = ContinuousClock()
            let transcriber = Transcriber.shared
            let downloaded = await transcriber.isModelDownloaded
            let load = try await clock.measure { try await transcriber.prepare { _ in } }
            print("TRANSCRIBE model \(downloaded ? "loaded" : "downloaded and loaded") in \(seconds(load)) s")
            var words: [Word] = []
            let run = try await clock.measure { words = try await transcriber.words(in: url, source: .system) }
            print("TRANSCRIBE \(words.count) words in \(seconds(run)) s")
            for w in words {
                print(String(format: "%7.2f %7.2f  %.2f  %@", w.start, w.end, w.confidence, w.text))
            }
            return words.isEmpty ? 1 : 0
        } catch {
            print("TRANSCRIBE FAIL \(error.localizedDescription)")
            return 1
        }
    }

    private static func transcribeMeeting(_ id: String, me: String) async -> Int32 {
        let started = Date()
        let library = MeetingLibrary(root: Store.root)
        do {
            let t = try await AfterCall.run(meetingID: id, library: library, transcriber: .shared, me: me)
            print("TRANSCRIBE done in \(Int(Date().timeIntervalSince(started))) s: \(t.lines.count) lines, \(t.removedEcho.count) echo lines removed")
            let names = library.meeting(id: id).map { AppDefaults.speakerNames($0.info, me: me) } ?? (me: me, them: "Them")
            print(t.markdown(me: names.me, them: names.them))
            return 0
        } catch {
            print("TRANSCRIBE FAIL \(error.localizedDescription)")
            return 1
        }
    }

    /// Runs `work` while keeping the main run loop turning (the after-call pass runs
    /// on the main actor), and returns its exit code.
    private static func wait(_ work: @escaping @MainActor () async -> Int32) -> Int32 {
        var code: Int32?
        Task { code = await work() }
        while code == nil { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
        return code ?? 1
    }

    private static func seconds(_ d: Duration) -> String {
        String(format: "%.1f", Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
    }
}
