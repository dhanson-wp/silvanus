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

@Suite("Call apps using input")
struct CallAppsUsingInputTests {
    private let me: Int32 = 100

    @Test func browserAndCallAppHelpersCountAsTheirApp() {
        let cases: [(String, String)] = [
            ("com.google.Chrome.helper", "com.google.Chrome"),
            ("com.google.Chrome", "com.google.Chrome"),
            ("company.thebrowser.browser.helper", "company.thebrowser.Browser"),
            ("org.mozilla.firefox.plugincontainer", "org.mozilla.firefox"),
            ("com.microsoft.edgemac.helper", "com.microsoft.edgemac"),
            ("us.zoom.CptHost", "us.zoom.xos"),
            ("com.microsoft.teams2.helper", "com.microsoft.teams2"),
            ("com.tinyspeck.slackmacgap.helper", "com.tinyspeck.slackmacgap"),
            ("com.apple.avconferenced", "com.apple.FaceTime"),
        ]
        for (id, app) in cases {
            #expect(CallApps.app(for: InputProcess(pid: 7, bundleID: id), ownPID: me) == app, "\(id)")
        }
    }

    @Test func lookalikesAndOtherAppsDoNotCount() {
        for id in ["com.google.Chromium", "com.apple.VoiceMemos", "com.apple.Siri", "com.microsoft.teamsX",
                   "us.zoomer.app", "", "com.apple.SafariTechnologyPreviewX"] {
            #expect(CallApps.app(for: InputProcess(pid: 7, bundleID: id), ownPID: me) == nil, "\(id)")
        }
        #expect(CallApps.app(for: InputProcess(pid: 7, bundleID: nil), ownPID: me) == nil)
    }

    @Test func webKitCountsOnlyForSafari() {
        let gpu = "com.apple.WebKit.GPU"
        #expect(CallApps.app(for: InputProcess(pid: 7, bundleID: gpu, responsibleBundleID: "com.apple.Safari"), ownPID: me)
            == "com.apple.Safari")
        #expect(CallApps.app(for: InputProcess(pid: 7, bundleID: gpu,
                                               path: "/Applications/Safari.app/Contents/XPCServices/x"), ownPID: me)
            == "com.apple.Safari")
        #expect(CallApps.app(for: InputProcess(pid: 7, bundleID: gpu, responsibleBundleID: "com.apple.mail"), ownPID: me) == nil)
        #expect(CallApps.app(for: InputProcess(pid: 7, bundleID: gpu), ownPID: me) == nil)
    }

    @Test func ourOwnProcessNeverCounts() {
        let processes = [InputProcess(pid: me, bundleID: "com.google.Chrome"),
                         InputProcess(pid: 8, bundleID: "com.apple.VoiceMemos")]
        #expect(CallApps.usingInput(processes, ownPID: me).isEmpty)
        let call = processes + [InputProcess(pid: 9, bundleID: "us.zoom.xos")]
        #expect(CallApps.usingInput(call, ownPID: me) == ["us.zoom.xos"])
    }

    /// Chrome open but not using input (an in-person meeting): no call, so no prompt, and the
    /// recording never stops on its own.
    @Test func anInPersonRecordingWithChromeOpenIsNoCall() {
        let usingInput = CallApps.usingInput([InputProcess(pid: me, bundleID: "com.derekhanson.silvanus")], ownPID: me)
        #expect(usingInput.isEmpty)
        #expect(CallEndStop(callAtStart: !usingInput.isEmpty, quickNote: false).phase == .off)
        let (_, event) = CallDetection.step(previous: .armed, micInUse: !usingInput.isEmpty, callApps: usingInput, recording: false)
        #expect(event == nil)
    }
}
