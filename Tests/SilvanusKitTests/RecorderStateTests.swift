import Foundation
import Testing
@testable import SilvanusKit

private let since = Date(timeIntervalSince1970: 1_793_975_400)

@Suite("Recorder state")
struct RecorderStateTests {
    @Test func aWholeRecordingGoesIdleToIdle() {
        var s = RecorderState()
        #expect(s.phase == .idle)
        do { let ok = s.apply(.start); #expect(ok) }
        #expect(s.phase == .starting)
        do { let ok = s.apply(.started(since)); #expect(ok) }
        #expect(s.phase == .recording(since: since))
        #expect(s.isRecording)
        do { let ok = s.apply(.stop); #expect(ok) }
        #expect(s.phase == .stopping)
        do { let ok = s.apply(.stopped); #expect(ok) }
        #expect(s.phase == .transcribing(progress: 0))
        do { let ok = s.apply(.progress(0.5)); #expect(ok) }
        #expect(s.phase == .transcribing(progress: 0.5))
        do { let ok = s.apply(.finished); #expect(ok) }
        #expect(s.phase == .idle)
    }

    @Test func failureLandsFromAnyPhase() {
        let phases: [RecorderPhase] = [.idle, .starting, .recording(since: since), .stopping,
                                       .transcribing(progress: 0.3), .failed("old")]
        for phase in phases {
            var s = RecorderState(phase: phase)
            do { let ok = s.apply(.fail("Couldn't write audio: disk full")); #expect(ok) }
            #expect(s.phase == .failed("Couldn't write audio: disk full"))
        }
    }

    @Test func startWhileRecordingIsRefused() {
        for phase: RecorderPhase in [.starting, .recording(since: since), .stopping] {
            var s = RecorderState(phase: phase)
            do { let ok = s.apply(.start); #expect(!ok) }
            #expect(s.phase == phase)
        }
    }

    /// A back-to-back call: the last meeting's transcription goes on behind the new recording.
    @Test func startWhileTranscribingOrFailedIsAllowed() {
        for phase: RecorderPhase in [.transcribing(progress: 0.4), .failed("x")] {
            var s = RecorderState(phase: phase)
            do { let ok = s.apply(.start); #expect(ok) }
            #expect(s.phase == .starting)
        }
    }

    @Test func transcriptionEventsOutsideTranscribingChangeNothing() {
        var s = RecorderState(phase: .recording(since: since))
        do { let ok = s.apply(.progress(0.7)); #expect(!ok) }
        do { let ok = s.apply(.finished); #expect(!ok) }
        #expect(s.phase == .recording(since: since))
    }

    @Test func stopOnlyWhileRecording() {
        for phase: RecorderPhase in [.idle, .starting, .stopping, .transcribing(progress: 0)] {
            var s = RecorderState(phase: phase)
            do { let ok = s.apply(.stop); #expect(!ok) }
        }
    }

    @Test func retryTranscribesFromIdleOrFailed() {
        var s = RecorderState(phase: .failed("Couldn't transcribe"))
        do { let ok = s.apply(.transcribe); #expect(ok) }
        #expect(s.phase == .transcribing(progress: 0))
        var idle = RecorderState()
        do { let ok = idle.apply(.transcribe); #expect(ok) }
        var busy = RecorderState(phase: .recording(since: since))
        do { let ok = busy.apply(.transcribe); #expect(!ok) }
    }

    @Test func dismissClearsAFailure() {
        var s = RecorderState(phase: .failed("x"))
        do { let ok = s.apply(.dismiss); #expect(ok) }
        #expect(s.phase == .idle)
        var r = RecorderState(phase: .recording(since: since))
        do { let ok = r.apply(.dismiss); #expect(!ok) }
    }

    @Test func progressIsClamped() {
        var s = RecorderState(phase: .transcribing(progress: 0))
        s.apply(.progress(1.7))
        #expect(s.phase == .transcribing(progress: 1))
    }

    @Test func thePillShowsOnlyWhileRecordingAndTheWindowIsNotKey() {
        #expect(RecorderState(phase: .recording(since: since)).showsPill(mainWindowIsKey: false))
        #expect(!RecorderState(phase: .recording(since: since)).showsPill(mainWindowIsKey: true))
        #expect(RecorderState(phase: .stopping).showsPill(mainWindowIsKey: false))
        #expect(!RecorderState(phase: .idle).showsPill(mainWindowIsKey: false))
        #expect(!RecorderState(phase: .transcribing(progress: 0)).showsPill(mainWindowIsKey: false))
    }
}

@Suite("Recording rules")
struct RecordingRulesTests {
    private func meeting(start: Date = since, source: String = "silvanus") -> Meeting {
        Meeting(info: MeetingInfo(title: "Acme kickoff", start: start, source: source))
    }

    @Test func recordsIntoAFreshMeetingWithoutAudio() {
        #expect(RecordingRules.canRecord(into: meeting(), hasAudio: false, hasTranscript: false, now: since.addingTimeInterval(600)))
    }

    @Test func neverIntoAMeetingWithAudioATranscriptOrAnImport() {
        let now = since.addingTimeInterval(600)
        #expect(!RecordingRules.canRecord(into: meeting(), hasAudio: true, hasTranscript: false, now: now))
        #expect(!RecordingRules.canRecord(into: meeting(), hasAudio: false, hasTranscript: true, now: now))
        #expect(!RecordingRules.canRecord(into: meeting(source: "granola"), hasAudio: false, hasTranscript: false, now: now))
    }

    @Test func neverIntoLastWeeksNotes() {
        #expect(!RecordingRules.canRecord(into: meeting(), hasAudio: false, hasTranscript: false,
                                          now: since.addingTimeInterval(13 * 3600)))
    }

    @Test func aNewRecordingIsTitledWithItsDateAndTime() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let title = RecordingRules.title(for: since, locale: Locale(identifier: "en_US"), timeZone: utc.timeZone)
        #expect(title == "Nov 6, 2026 at 2:30 PM")
    }

    @Test func recordingSinceIsAStaticClockTime() {
        let text = RecordingRules.since(since, locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)
        #expect(text == "Recording since 2:30 PM")
    }

    @Test func segmentFilesAreFoundByTrack() {
        let files = ["mic-0001.caf", "mic-0002.caf", "system-0001.caf", "mic.caf", "tracks.json", "probe-0001.caf"]
        #expect(RecordingRules.segments(in: files, track: "mic") == ["mic-0001.caf", "mic-0002.caf"])
        #expect(RecordingRules.segments(in: files, track: "system") == ["system-0001.caf"])
        #expect(RecordingRules.hasSegments(files))
        #expect(!RecordingRules.hasSegments(["mic.caf", "tracks.json"]))
    }

    @Test func anInterruptedRecordingHasSegmentsAndNoTranscript() {
        #expect(RecordingRules.isInterrupted(audioFiles: ["mic-0001.caf"], hasTranscript: false))
        #expect(!RecordingRules.isInterrupted(audioFiles: ["mic-0001.caf"], hasTranscript: true))
        #expect(!RecordingRules.isInterrupted(audioFiles: [], hasTranscript: false))
    }
}

@Suite("Note times")
struct NoteTimesTests {
    @Test func newLinesGetTheTimeTheyAppeared() {
        var times = NoteTimes()
        times.update(old: "", new: "Agenda\n", now: 12)
        times.update(old: "Agenda\n", new: "Agenda\nBudget moves to Thursday\n", now: 75)
        #expect(times.time(for: "Agenda") == 12)
        #expect(times.time(for: "Budget moves to Thursday") == 75)
    }

    @Test func aLineBeingTypedKeepsItsFirstTime() {
        var times = NoteTimes()
        times.update(old: "", new: "Bud", now: 10)
        times.update(old: "Bud", new: "Budget", now: 11)
        times.update(old: "Budget", new: "Budget moves", now: 14)
        #expect(times.time(for: "Budget moves") == 10)
        // Only lines in the note are kept.
        #expect(times.count == 1)
    }

    @Test func blankLinesGetNoTime() {
        var times = NoteTimes()
        times.update(old: "", new: "Agenda\n\n   \nNext", now: 5)
        #expect(times.time(for: "") == nil)
        #expect(times.time(for: "   ") == nil)
        #expect(times.count == 2)
    }

    @Test func afterRecordingEditsCarryTimesButAddNone() {
        var times = NoteTimes()
        times.update(old: "", new: "Agenda", now: 5)
        times.update(old: "Agenda", new: "Agenda items\nA new line", now: nil)
        #expect(times.time(for: "Agenda items") == 5)
        #expect(times.time(for: "A new line") == nil)
    }

    @Test func linesAboveDoNotShiftTimes() {
        var times = NoteTimes()
        times.update(old: "", new: "One\nTwo", now: 5)
        times.update(old: "One\nTwo", new: "Zero\nOne\nTwo", now: 30)
        #expect(times.time(for: "Zero") == 30)
        #expect(times.time(for: "One") == 5)
        #expect(times.time(for: "Two") == 5)
    }

    @Test func theHashIsStableAcrossRuns() {
        // FNV-1a 64 of "Agenda", never Swift's per-process hashValue.
        #expect(NoteTimes.hash("Agenda") == NoteTimes.hash("Agenda"))
        // FNV-1a 64 of the empty string is its offset basis.
        #expect(NoteTimes.hash("") == "cbf29ce484222325")
        #expect(NoteTimes.hash("Agenda").count == 16)
        #expect(NoteTimes.hash("Agenda") != NoteTimes.hash("agenda"))
    }

    @Test func roundTripsAsJSON() throws {
        var times = NoteTimes()
        times.update(old: "", new: "Agenda\nBudget", now: 65)
        let data = try times.json()
        let back = try NoteTimes(json: data)
        #expect(back == times)
        #expect(back.time(for: "Budget") == 65)
    }
}

@Suite("Note times on disk")
struct NoteTimesLibraryTests {
    @Test func savedBesideTheNotesAndReadBack() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "silvanus-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = MeetingLibrary(root: root, trash: { try FileManager.default.removeItem(at: $0) })
        let m = Meeting(info: MeetingInfo(title: "Acme kickoff", start: since), notes: "Agenda")
        let folder = try library.save(m)
        #expect(library.readNoteTimes(for: m.id) == nil)
        var times = NoteTimes()
        times.update(old: "", new: "Agenda", now: 3)
        try library.saveNoteTimes(times, for: m.id)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: MeetingFolder.noteTimes).path))
        #expect(library.readNoteTimes(for: m.id) == times)
        // The notes are never rewritten.
        #expect(library.readNotes(for: m.id) == "Agenda")
    }
}

@Suite("Fix round 1")
struct RecorderFixTests {
    @Test func aMovedLineDoesNotLendItsTimeToANewLineInItsPlace() {
        var times = NoteTimes()
        times.update(old: "", new: "Alpha\nBeta\nGamma", now: 5)
        // Alpha moves to the end, and a new line takes its old place.
        times.update(old: "Alpha\nBeta\nGamma", new: "Delta\nBeta\nGamma\nAlpha", now: 40)
        #expect(times.time(for: "Delta") == 40)
        #expect(times.time(for: "Alpha") == 5)
    }

    @Test func duplicateLinesShareOneTime() {
        var times = NoteTimes()
        times.update(old: "", new: "Next", now: 5)
        times.update(old: "Next", new: "Next\nNext", now: 30)
        #expect(times.time(for: "Next") == 5)
        #expect(times.count == 1)
    }

    @Test func autoRetryStopsAfterThreeFailures() {
        #expect(RecordingRules.shouldAutoRetry(attempts: 0))
        #expect(RecordingRules.shouldAutoRetry(attempts: 2))
        #expect(!RecordingRules.shouldAutoRetry(attempts: 3))
        #expect(RecordingRules.maxAttempts == 3)
    }

    @Test func attemptsAreKeptInTheAudioFolder() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "silvanus-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let library = MeetingLibrary(root: root, trash: { try FileManager.default.removeItem(at: $0) })
        let m = Meeting(info: MeetingInfo(title: "Acme kickoff", start: since))
        try library.save(m)
        #expect(library.transcriptionAttempts(for: m.id) == 0)
        try library.setTranscriptionAttempts(2, for: m.id)
        #expect(library.transcriptionAttempts(for: m.id) == 2)
        #expect(FileManager.default.fileExists(atPath: library.audioURL(for: m.id)!.appending(path: MeetingFolder.attempts).path))
        try library.setTranscriptionAttempts(0, for: m.id)
        #expect(library.transcriptionAttempts(for: m.id) == 0)
    }
}
