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

    @Test func theControlsShowForTheWholeRecording() {
        #expect(RecorderState(phase: .recording(since: since)).showsControls)
        #expect(RecorderState(phase: .paused(elapsed: 5)).showsControls)
        #expect(RecorderState(phase: .interrupted(elapsed: 5, reason: "x")).showsControls)
        #expect(!RecorderState(phase: .stopping).showsControls)
        #expect(!RecorderState(phase: .idle).showsControls)
        #expect(!RecorderState(phase: .transcribing(progress: 0)).showsControls)
    }

    @Test func pauseHoldsTheCapturedTimeAndResumeGoesOn() {
        var s = RecorderState(phase: .recording(since: since))
        do { let ok = s.apply(.pause(since.addingTimeInterval(60))); #expect(ok) }
        #expect(s.phase == .paused(elapsed: 60))
        #expect(s.isRecording && s.isPaused && !s.isCapturing)
        // Ten minutes paused: the time holds.
        #expect(s.elapsed(at: since.addingTimeInterval(660)) == 60)
        do { let ok = s.apply(.resume(since.addingTimeInterval(660))); #expect(ok) }
        #expect(s.phase == .recording(since: since.addingTimeInterval(600)))
        // Thirty seconds later: 90 seconds captured, the pause left out.
        #expect(s.elapsed(at: since.addingTimeInterval(690)) == 90)
    }

    @Test func pauseAndResumeOnlyFitTheirPhases() {
        var paused = RecorderState(phase: .paused(elapsed: 3))
        do { let ok = paused.apply(.pause(since)); #expect(!ok) }
        var recording = RecorderState(phase: .recording(since: since))
        do { let ok = recording.apply(.resume(since)); #expect(!ok) }
        for phase: RecorderPhase in [.idle, .starting, .stopping, .transcribing(progress: 0)] {
            var s = RecorderState(phase: phase)
            do { let ok = s.apply(.pause(since)); #expect(!ok) }
            do { let ok = s.apply(.resume(since)); #expect(!ok) }
        }
    }

    @Test func pauseWhileInterruptedIsNotAllowed() {
        var s = RecorderState(phase: .interrupted(elapsed: 42, reason: "The microphone stopped"))
        do { let ok = s.apply(.pause(since)); #expect(!ok) }
        do { let ok = s.apply(.resume(since)); #expect(!ok) }
        #expect(s.phase == .interrupted(elapsed: 42, reason: "The microphone stopped"))
    }

    @Test func anInterruptionHoldsTimeAndRetryGoesOn() {
        var s = RecorderState(phase: .recording(since: since))
        do { let ok = s.apply(.interrupt(since.addingTimeInterval(30), "The microphone stopped")); #expect(ok) }
        #expect(s.phase == .interrupted(elapsed: 30, reason: "The microphone stopped"))
        #expect(s.isRecording && s.isInterrupted)
        #expect(s.elapsed(at: since.addingTimeInterval(500)) == 30)
        do { let ok = s.apply(.recovered(since.addingTimeInterval(100))); #expect(ok) }
        #expect(s.elapsed(at: since.addingTimeInterval(110)) == 40)
    }

    @Test func aTrackCanFailWhilePaused() {
        var s = RecorderState(phase: .paused(elapsed: 12))
        do { let ok = s.apply(.interrupt(since, "The microphone stopped")); #expect(ok) }
        #expect(s.phase == .interrupted(elapsed: 12, reason: "The microphone stopped"))
    }

    @Test func retryAfterAFailureWhilePausedReturnsToPaused() {
        var s = RecorderState(phase: .paused(elapsed: 12))
        s.apply(.interrupt(since, "The microphone stopped"))
        do { let ok = s.apply(.recoveredToPause); #expect(ok) }
        #expect(s.phase == .paused(elapsed: 12))
        var r = RecorderState(phase: .recording(since: since))
        do { let ok = r.apply(.recoveredToPause); #expect(!ok) }
    }

    @Test func recoveredOnlyAfterAnInterruption() {
        var s = RecorderState(phase: .paused(elapsed: 12))
        do { let ok = s.apply(.recovered(since)); #expect(!ok) }
    }

    @Test func stopWhilePausedOrInterruptedFinalizes() {
        for phase: RecorderPhase in [.paused(elapsed: 12), .interrupted(elapsed: 12, reason: "x")] {
            var s = RecorderState(phase: phase)
            do { let ok = s.apply(.stop); #expect(ok) }
            #expect(s.phase == .stopping)
            do { let ok = s.apply(.stopped); #expect(ok) }
            #expect(s.phase == .transcribing(progress: 0))
        }
    }

    @Test func startIsRefusedWhilePausedOrInterrupted() {
        for phase: RecorderPhase in [.paused(elapsed: 1), .interrupted(elapsed: 1, reason: "x")] {
            var s = RecorderState(phase: phase)
            do { let ok = s.apply(.start); #expect(!ok) }
        }
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

@Suite("Stop when the call ends")
struct CallEndStopTests {
    /// Steps once a second from `from` for `seconds`, returning the first action.
    private func run(_ rule: inout CallEndStop, from: TimeInterval, seconds: Int, callInput: Bool = false,
                     capturing: Bool = true, enabled: Bool = true) -> (action: CallEndStop.Action?, at: TimeInterval) {
        for s in 0...seconds {
            let t = from + TimeInterval(s)
            if let action = rule.step(at: since.addingTimeInterval(t), callInput: callInput, capturing: capturing,
                                      enabled: enabled) {
                return (action, t)
            }
        }
        return (nil, from + TimeInterval(seconds))
    }

    @Test func aCallStartedRecordingCountsDownAfter15QuietSecondsThenStops() {
        var rule = CallEndStop(callAtStart: true, quickNote: false)
        _ = rule.step(at: since, callInput: true, capturing: true, enabled: true)
        #expect(rule.stopAt == nil)
        // The call app lets go of the microphone at 1 s.
        _ = rule.step(at: since.addingTimeInterval(1), callInput: false, capturing: true, enabled: true)
        _ = rule.step(at: since.addingTimeInterval(15.9), callInput: false, capturing: true, enabled: true)
        #expect(rule.stopAt == nil, "not before 15 s of no call input")
        _ = rule.step(at: since.addingTimeInterval(16), callInput: false, capturing: true, enabled: true)
        #expect(rule.stopAt == since.addingTimeInterval(26))
        #expect(rule.secondsLeft(at: since.addingTimeInterval(16)) == 10)
        #expect(rule.secondsLeft(at: since.addingTimeInterval(25.2)) == 1)
        #expect(rule.step(at: since.addingTimeInterval(25.9), callInput: false, capturing: true, enabled: true) == nil)
        #expect(rule.step(at: since.addingTimeInterval(26), callInput: false, capturing: true, enabled: true) == .stop)
        // Once only.
        #expect(rule.phase == .off)
        #expect(rule.step(at: since.addingTimeInterval(40), callInput: false, capturing: true, enabled: true) == nil)
    }

    @Test func reachingZeroFinalizesExactlyLikeStop() {
        var rule = CallEndStop(callAtStart: true, quickNote: false)
        var state = RecorderState(phase: .recording(since: since))
        let (action, _) = run(&rule, from: 0, seconds: 60)
        #expect(action == .stop)
        // The recorder applies the same events Stop does.
        do { let ok = state.apply(.stop); #expect(ok) }
        do { let ok = state.apply(.stopped); #expect(ok) }
        #expect(state.phase == .transcribing(progress: 0))
    }

    @Test func callInputComingBackCancelsTheCountdown() {
        var rule = CallEndStop(callAtStart: true, quickNote: false)
        _ = run(&rule, from: 0, seconds: 16)
        #expect(rule.stopAt != nil)
        _ = rule.step(at: since.addingTimeInterval(18), callInput: true, capturing: true, enabled: true)
        #expect(rule.stopAt == nil)
        #expect(rule.phase == .watching(quietSince: nil))
        // The quiet starts over.
        let (action, at) = run(&rule, from: 19, seconds: 60)
        #expect(action == .stop)
        #expect(at == 19 + 15 + 10)
    }

    @Test func keepRecordingSuppressesUntilANewCallStarts() {
        var rule = CallEndStop(callAtStart: true, quickNote: false)
        _ = run(&rule, from: 0, seconds: 16)
        #expect(rule.stopAt != nil)
        rule.keepRecording()
        #expect(rule.stopAt == nil)
        #expect(run(&rule, from: 17, seconds: 600).action == nil, "kept for as long as no call starts")
        // A new call starts using the microphone, then ends: the countdown comes back.
        _ = rule.step(at: since.addingTimeInterval(700), callInput: true, capturing: true, enabled: true)
        #expect(rule.phase == .watching(quietSince: nil))
        let (action, at) = run(&rule, from: 701, seconds: 60)
        #expect(action == .stop)
        #expect(at == 701 + 25)
    }

    @Test func noCountdownWhilePaused() {
        var rule = CallEndStop(callAtStart: true, quickNote: false)
        #expect(run(&rule, from: 0, seconds: 600, capturing: false).action == nil)
        #expect(rule.stopAt == nil)
        // Paused during the countdown cancels it; after Resume the quiet starts over.
        _ = run(&rule, from: 600, seconds: 16)
        #expect(rule.stopAt != nil)
        _ = rule.step(at: since.addingTimeInterval(620), callInput: false, capturing: false, enabled: true)
        #expect(rule.stopAt == nil)
        let (action, at) = run(&rule, from: 700, seconds: 60)
        #expect(action == .stop)
        #expect(at == 725)
    }

    @Test func quickNoteAndRecordingsWithNoCallNeverStop() {
        for (call, quick) in [(true, true), (false, true), (false, false)] {
            var rule = CallEndStop(callAtStart: call, quickNote: quick)
            #expect(rule.phase == .off)
            #expect(run(&rule, from: 0, seconds: 600).action == nil)
            // Even a call app that starts later doesn't make it a call recording.
            _ = rule.step(at: since.addingTimeInterval(601), callInput: true, capturing: true, enabled: true)
            #expect(run(&rule, from: 602, seconds: 600).action == nil)
            rule.keepRecording()
            #expect(rule.phase == .off)
        }
    }

    @Test func theSettingOffNeverCountsDown() {
        var rule = CallEndStop(callAtStart: true, quickNote: false)
        #expect(run(&rule, from: 0, seconds: 600, enabled: false).action == nil)
        _ = run(&rule, from: 600, seconds: 16)
        #expect(rule.stopAt != nil)
        _ = rule.step(at: since.addingTimeInterval(617), callInput: false, capturing: true, enabled: false)
        #expect(rule.stopAt == nil, "turning it off mid-countdown cancels")
    }

    @Test func theWords() {
        #expect(RecordingWords.callEndedNote(seconds: 10) == "Call ended. Stopping in 10 seconds.")
        #expect(RecordingWords.stoppingIn(1) == "Stopping in 1 second")
        #expect(RecordingWords.keepRecording == "Keep recording")
    }
}

@Suite("Stop when the call ends, muted")
struct CallEndStopMutedTests {
    private func step(_ rule: inout CallEndStop, _ t: TimeInterval, input: Bool, output: Bool) -> CallEndStop.Action? {
        rule.step(at: since.addingTimeInterval(t), callInput: input, callOutput: output, capturing: true, enabled: true)
    }

    @Test func aMutedListenerNeverCountsDown() {
        var rule = CallEndStop(callAtStart: true, quickNote: false)
        _ = step(&rule, 0, input: true, output: true)
        // Muted: the call app lets go of the microphone but still plays the call.
        for t in 1...3600 {
            #expect(step(&rule, TimeInterval(t), input: false, output: true) == nil)
        }
        #expect(rule.stopAt == nil)
    }

    @Test func hangingUpWithNeitherCountsDownAndStops() {
        var rule = CallEndStop(callAtStart: true, quickNote: false)
        _ = step(&rule, 0, input: false, output: true)
        var stoppedAt: Int?
        for t in 1...60 where stoppedAt == nil {
            if step(&rule, TimeInterval(t), input: false, output: false) == .stop { stoppedAt = t }
        }
        #expect(stoppedAt == 1 + 15 + 10)
    }

    @Test func outputComingBackCancels() {
        var rule = CallEndStop(callAtStart: true, quickNote: false)
        for t in 0...15 { _ = step(&rule, TimeInterval(t), input: false, output: false) }
        #expect(rule.stopAt != nil)
        _ = step(&rule, 16, input: false, output: true)
        #expect(rule.stopAt == nil)
        #expect(rule.phase == .watching(quietSince: nil))
    }

    @Test func keptWaitsForTheMicrophoneNotOutput() {
        var rule = CallEndStop(callAtStart: true, quickNote: false)
        for t in 0...15 { _ = step(&rule, TimeInterval(t), input: false, output: false) }
        rule.keepRecording()
        _ = step(&rule, 20, input: false, output: true)
        #expect(rule.phase == .kept)
        _ = step(&rule, 21, input: true, output: true)
        #expect(rule.phase == .watching(quietSince: nil))
    }

    @Test func theNoteCountsDownOneSecondAtATime() {
        let stopAt = since.addingTimeInterval(10)
        let texts = (0..<10).map { RecordingWords.callEndedNote(seconds: CallEndStop.secondsLeft(until: stopAt,
                                                                   at: since.addingTimeInterval(TimeInterval($0)))) }
        #expect(texts.prefix(3) == ["Call ended. Stopping in 10 seconds.", "Call ended. Stopping in 9 seconds.",
                                    "Call ended. Stopping in 8 seconds."])
        #expect(texts.last == "Call ended. Stopping in 1 second.")
    }
}

@Suite("Call apps using output")
struct CallAppsOutputTests {
    @Test func outputAndInputComeFromOneRead() {
        let me: Int32 = 42
        let processes = [
            InputProcess(pid: 7, bundleID: "com.google.Chrome.helper", isRunningInput: false, isRunningOutput: true),
            InputProcess(pid: 8, bundleID: "us.zoom.xos", isRunningInput: true, isRunningOutput: true),
            InputProcess(pid: me, bundleID: "com.apple.FaceTime", isRunningInput: true, isRunningOutput: true),
            InputProcess(pid: 9, bundleID: "com.apple.Music", isRunningInput: false, isRunningOutput: true),
        ]
        let audio = CallApps.audio(processes, ownPID: me)
        #expect(audio.input == ["us.zoom.xos"])
        #expect(audio.output == ["com.google.Chrome", "us.zoom.xos"])
    }
}
