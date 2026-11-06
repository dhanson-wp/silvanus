import CoreGraphics
import Foundation
import Testing
@testable import SilvanusKit

private let start = Date(timeIntervalSince1970: 1_793_975_400)

@Suite("Capture timeline")
struct CaptureTimelineTests {
    @Test func capturedTimeLeavesOutHolds() {
        var t = CaptureTimeline(start: start)
        #expect(t.captured(at: start.addingTimeInterval(10)) == 10)
        t.hold(at: start.addingTimeInterval(10))
        #expect(t.isHeld)
        #expect(t.captured(at: start.addingTimeInterval(70)) == 10)
        t.release(at: start.addingTimeInterval(70))
        #expect(t.captured(at: start.addingTimeInterval(75)) == 15)
        t.hold(at: start.addingTimeInterval(80))
        t.hold(at: start.addingTimeInterval(90))
        t.release(at: start.addingTimeInterval(100))
        #expect(t.captured(at: start.addingTimeInterval(100)) == 20)
    }

    @Test func releaseWithoutAHoldChangesNothing() {
        var t = CaptureTimeline(start: start)
        t.release(at: start.addingTimeInterval(5))
        #expect(t.captured(at: start.addingTimeInterval(5)) == 5)
    }
}

@Suite("Level bars")
struct LevelMathTests {
    @Test func quietIsFlatAndLoudIsFull() {
        #expect(LevelMath.level(rms: 0) == 0)
        #expect(LevelMath.level(rms: 0.001) == 0)    // −60 dBFS, a quiet room
        #expect(LevelMath.level(rms: 0.5) == 1)
        let speech = LevelMath.level(rms: 0.03)        // about −30 dBFS
        #expect(speech > 0.4 && speech < 0.7)
        #expect(LevelMath.level(rms: .nan) == 0)
    }

    @Test func smoothingRisesAtOnceAndFallsSoftly() {
        #expect(LevelMath.smooth(previous: 0.2, next: 0.8) == 0.8)
        let fallen = LevelMath.smooth(previous: 0.8, next: 0)
        #expect(fallen > 0.3 && fallen < 0.8)
        #expect(LevelMath.smooth(previous: 0.05, next: 0) == 0)
    }

    @Test func theRateIsBounded() {
        #expect(LevelMath.maxRate <= 15)
    }
}

@Suite("Recording controls placement")
struct BarPlacementTests {
    private let size = CGSize(width: 264, height: 48)
    private let main = BarPlacement.Screen(id: "1", visible: CGRect(x: 0, y: 80, width: 1440, height: 795))
    private let side = BarPlacement.Screen(id: "2", visible: CGRect(x: 1440, y: 0, width: 1920, height: 1055))

    @Test func theDefaultIsBottomCenterAboveTheDock() {
        let origin = BarPlacement.defaultOrigin(size: size, in: main.visible, inset: 16)
        #expect(origin == CGPoint(x: 588, y: 96))
    }

    @Test func clampKeepsTheBarAndItsNoteOnScreen() {
        #expect(BarPlacement.clamp(CGPoint(x: -50, y: 2000), size: size, in: main.visible) == CGPoint(x: 0, y: 827))
        #expect(BarPlacement.clamp(CGPoint(x: 1400, y: 0), size: size, above: 40, in: main.visible) == CGPoint(x: 1176, y: 80))
        #expect(BarPlacement.clamp(CGPoint(x: 100, y: 820), size: size, above: 40, in: main.visible).y == 787)
    }

    @Test func thePositionIsRememberedPerDisplay() {
        let saved = ["1": CGPoint(x: 100, y: 200), "2": CGPoint(x: 2000, y: 500)]
        let onSide = BarPlacement.resolve(saved: saved, last: "2", preferred: "1", screens: [main, side], size: size, inset: 16)
        #expect(onSide?.screen.id == "2" && onSide?.origin == CGPoint(x: 2000, y: 500))
        let sideGone = BarPlacement.resolve(saved: saved, last: "2", preferred: "1", screens: [main], size: size, inset: 16)
        #expect(sideGone?.screen.id == "1" && sideGone?.origin == CGPoint(x: 100, y: 200))
    }

    @Test func aNewDisplayGetsTheDefault() {
        let fresh = BarPlacement.resolve(saved: [:], last: nil, preferred: "2", screens: [main, side], size: size, inset: 16)
        #expect(fresh?.screen.id == "2" && fresh?.origin == CGPoint(x: 2268, y: 16))
    }

    @Test func aSavedSpotOffAShrunkScreenIsPulledBack() {
        let saved = ["1": CGPoint(x: 1300, y: 860)]
        let resolved = BarPlacement.resolve(saved: saved, last: "1", preferred: "1", screens: [main], size: size, inset: 16)
        #expect(resolved?.origin == CGPoint(x: 1176, y: 827))
    }

    @Test func theScreenIsTheOneShowingMostOfTheBar() {
        let rect = CGRect(x: 1400, y: 300, width: 264, height: 48)
        #expect(BarPlacement.screen(for: rect, in: [main, side])?.id == "2")
        let lost = CGRect(x: 5000, y: 300, width: 264, height: 48)
        #expect(BarPlacement.screen(for: lost, in: [main, side])?.id == "2")
    }
}

@Suite("Recording words")
struct RecordingWordsTests {
    @Test func thePromptNamesTheAppOnlyWhenItKnowsIt() {
        let named = RecordingWords.prompt(appName: "FaceTime")
        #expect(named.title == "Meeting detected")
        #expect(named.source == "Silvanus · FaceTime is using your microphone")
        #expect(named.question == "Start recording this meeting?")
        #expect(named.record == "Record meeting" && named.notNow == "Not now")
        let plain = RecordingWords.prompt(appName: nil)
        #expect(plain.title == "Microphone in use" && plain.question == "Start a recording?")
        #expect(RecordingWords.prompt(appName: "").title == "Microphone in use")
    }

    @Test func theTimeSuffixFollowsTheState() {
        #expect(RecordingWords.timeSuffix(paused: false, interrupted: false) == "elapsed")
        #expect(RecordingWords.timeSuffix(paused: true, interrupted: false) == "paused")
        #expect(RecordingWords.timeSuffix(paused: false, interrupted: true) == "stopped")
    }
}
