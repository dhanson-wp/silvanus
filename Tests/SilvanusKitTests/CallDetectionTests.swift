import Foundation
import Testing
@testable import SilvanusKit

@Suite("Call detection")
struct CallDetectionTests {
    private let zoom: Set<String> = ["us.zoom.xos"]

    /// Runs polls from `state`, returning the last state and every event.
    private func run(from state: CallDetection.State = .armed,
                     _ polls: [(mic: Bool, apps: Set<String>, recording: Bool)]) -> (CallDetection.State, [CallDetection.Event]) {
        var state = state
        var events: [CallDetection.Event] = []
        for poll in polls {
            let (next, event) = CallDetection.step(previous: state, micInUse: poll.mic, callApps: poll.apps,
                                                   recording: poll.recording)
            state = next
            if let event { events.append(event) }
        }
        return (state, events)
    }

    @Test func startFiresOncePerCall() {
        let polls = Array(repeating: (mic: true, apps: zoom, recording: false), count: 30)
        let (state, events) = run(polls)
        #expect(events == [.meetingStarted])
        #expect(state == .inCall(quietFor: 0))
    }

    @Test func nothingWhileSilvanusRecords() {
        let polls = Array(repeating: (mic: true, apps: zoom, recording: true), count: 10)
        #expect(run(polls).1.isEmpty)
        // Stopping mid-call announces nothing either: the call was already recorded.
        let after = polls + Array(repeating: (mic: true, apps: zoom, recording: false), count: 10)
        #expect(run(after).1.isEmpty)
    }

    @Test func nothingWhenNoCallAppRuns() {
        let polls = Array(repeating: (mic: true, apps: Set<String>(), recording: false), count: 10)
        let (state, events) = run(polls)
        #expect(events.isEmpty)
        #expect(state == .armed)
        // Nor when a call app runs but the microphone is free.
        #expect(run(Array(repeating: (mic: false, apps: zoom, recording: false), count: 10)).1.isEmpty)
    }

    @Test func reArmsAfterTheMicIsReleasedForTenSeconds() {
        let call = (mic: true, apps: zoom, recording: false)
        let free = (mic: false, apps: zoom, recording: false)
        // Free for 8 seconds (4 polls) isn't enough: the same call goes on.
        let (_, short) = run([call] + Array(repeating: free, count: 4) + [call])
        #expect(short == [.meetingStarted])
        // Free for 10 seconds (5 polls): the next call is announced.
        let (_, long) = run([call] + Array(repeating: free, count: 5) + [call])
        #expect(long == [.meetingStarted, .meetingStarted])
    }

    @Test func aMomentOfMicAgainResetsTheQuietTime() {
        let call = (mic: true, apps: zoom, recording: false)
        let free = (mic: false, apps: zoom, recording: false)
        let (state, _) = run([call, free, free, free, call, free, free])
        #expect(state == .inCall(quietFor: 4))
    }

    @Test func callAppsAreFoundByBundleID() {
        let running: [String?] = ["com.apple.finder", "us.zoom.xos", nil, "com.google.Chrome", "com.apple.Notes"]
        #expect(CallApps.running(in: running) == ["us.zoom.xos", "com.google.Chrome"])
        for id in ["com.microsoft.teams2", "com.microsoft.teams", "com.tinyspeck.slackmacgap", "com.apple.FaceTime",
                   "com.cisco.webexmeetingsapp", "company.thebrowser.Browser", "com.apple.Safari",
                   "org.mozilla.firefox", "com.microsoft.edgemac"] {
            #expect(CallApps.bundleIDs.contains(id))
        }
    }
}

@Suite("Call audio warning")
struct CallAudioWarningTests {
    @Test func quickNoteNeverWarnsAboutCallAudio() {
        for atStart in [false, true] {
            for now in [false, true] {
                #expect(!CallAudioWarning.applies(quickNote: true, callAppAtStart: atStart, callAppNow: now))
                #expect(CallAudioWarning.warning(quickNote: true, callAppAtStart: atStart, callAppNow: now,
                                                 silentFor: 600, threshold: 30) == nil)
            }
        }
    }

    @Test func noCallAppAtStartOrNowNeverWarns() {
        #expect(CallAudioWarning.warning(quickNote: false, callAppAtStart: false, callAppNow: false,
                                         silentFor: 600, threshold: 30) == nil)
    }

    @Test func duringACallSilenceWarnsWithTheExactWords() {
        let text = "Nobody on the call is audible yet. Check System Audio access in Settings."
        #expect(CallAudioWarning.warning(quickNote: false, callAppAtStart: true, callAppNow: false,
                                         silentFor: 31, threshold: 30) == text)
        // A call app opened after the recording started counts too.
        #expect(CallAudioWarning.warning(quickNote: false, callAppAtStart: false, callAppNow: true,
                                         silentFor: 31, threshold: 30) == text)
    }

    @Test func notBeforeTheThreshold() {
        #expect(CallAudioWarning.warning(quickNote: false, callAppAtStart: true, callAppNow: true,
                                         silentFor: 29, threshold: 30) == nil)
    }
}
