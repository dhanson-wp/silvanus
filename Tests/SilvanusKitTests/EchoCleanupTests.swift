import Foundation
import Testing
@testable import SilvanusKit

/// Levels for a made-up recording: `seconds` long, the call talking over `callTalks`,
/// me talking over `iTalk`. The call is at -20, its leak in the mic 30 dB lower, and
/// my voice at -25 in the mic.
private func levels(seconds: Double, callTalks: [ClosedRange<Double>], iTalk: [ClosedRange<Double>]) -> TrackLevels {
    let count = Int(seconds / TrackLevels.frame)
    var mic = [Float](repeating: -90, count: count)
    var call = [Float](repeating: -90, count: count)
    for index in 0..<count {
        let time = Double(index) * TrackLevels.frame
        if callTalks.contains(where: { $0.contains(time) }) { call[index] = -20; mic[index] = -50 }
        if iTalk.contains(where: { $0.contains(time) }) { mic[index] = -25 }
    }
    return TrackLevels(mic: mic, call: call)
}

@Suite("Echo cleanup") struct EchoCleanupTests {
    @Test("The leak is how much quieter the call is in the mic")
    func leakIsMeasured() {
        let l = levels(seconds: 60, callTalks: [10...40], iTalk: [45...50])
        #expect(EchoCleanup.leak(l) == -30)
    }

    @Test("Under 5 seconds of call audio there's no leak to measure, and every word is kept")
    func tooLittleCallAudio() {
        let l = levels(seconds: 60, callTalks: [10...13], iTalk: [])
        #expect(EchoCleanup.leak(l) == nil)
        let words = testWords("this could be anything at all", from: 10)
        #expect(EchoCleanup.gate(words, levels: l).removed.isEmpty)
    }

    @Test("A mic word no louder than the leak, while the call talks, is bleed")
    func quietWordsUnderTheCallAreRemoved() {
        let l = levels(seconds: 60, callTalks: [10...40], iTalk: [45...50])
        let bleed = testWords("the launch moves to friday", from: 20)
        let mine = testWords("sounds good to me", from: 45)
        let result = EchoCleanup.gate(bleed + mine, levels: l)
        #expect(result.removed == bleed)
        #expect(result.kept == mine)
    }

    @Test("Talking over the call keeps my words: my voice is far above the leak")
    func talkingOverTheCallIsKept() {
        let l = levels(seconds: 60, callTalks: [10...40], iTalk: [20...24])
        let mine = testWords("sorry to jump in here", from: 20)
        #expect(EchoCleanup.gate(mine, levels: l).kept == mine)
    }

    @Test("A headset with no leak keeps everything")
    func cleanHeadset() {
        var l = levels(seconds: 60, callTalks: [10...40], iTalk: [])
        l.mic = l.mic.map { _ in -90 }
        for index in Int(20 / TrackLevels.frame)..<Int(24 / TrackLevels.frame) { l.mic[index] = -25 }
        let mine = testWords("yes that works for me", from: 20)
        #expect(EchoCleanup.gate(mine, levels: l).kept == mine)
    }

    @Test("A run of words the call also says within 2 seconds is bleed")
    func repeatedRunIsRemoved() {
        let call = testWords("we should ship the new editor on thursday", from: 10)
        let bleed = testWords("ship the new editor on", from: 11)
        let mine = testWords("I disagree with that plan entirely", from: 30)
        let result = EchoCleanup.dedupe(bleed + mine, against: call)
        #expect(result.removed == bleed)
        #expect(result.kept == mine)
    }

    @Test("One shared word in the middle of my own sentence is kept")
    func oneSharedWordIsKept() {
        let call = testWords("the editor is ready", from: 10)
        let mine = testWords("I think our editor needs more work", from: 10)
        #expect(EchoCleanup.dedupe(mine, against: call).kept == mine)
    }

    @Test("The same words more than 2 seconds apart are kept")
    func farApartIsKept() {
        let call = testWords("ship the new editor", from: 10)
        let mine = testWords("ship the new editor", from: 20)
        #expect(EchoCleanup.dedupe(mine, against: call).kept == mine)
    }

    @Test("Without real bleed, agreeing in the call's own words is never removed")
    func agreeingOnACleanHeadset() {
        var l = levels(seconds: 60, callTalks: [10...40], iTalk: [])
        l.mic = l.mic.map { _ in -90 }
        let call = testWords("so we ship on thursday", from: 30)
        let mine = testWords("ship on thursday", from: 31.5)
        for index in Int(31.5 / TrackLevels.frame)..<Int(34 / TrackLevels.frame) { l.mic[index] = -25 }
        #expect(EchoCleanup.clean(mine, call: call, levels: l).kept == mine)
    }

    @Test("The transcript keeps what cleanup removed, as lines in time order")
    func removedWordsAreKeptAside() {
        let l = levels(seconds: 120, callTalks: [10...40, 60...100], iTalk: [45...50])
        let call = testWords("the launch moves to friday and the budget review moves to thursday", from: 20)
            + testWords("priya will share the checklist before the next meeting everyone", from: 70)
        let bleed = testWords("the launch moves to friday and the budget review moves to thursday", from: 20.2)
            + testWords("priya will share the checklist before the next meeting everyone", from: 70.2)
        let mine = testWords("sounds good to me", from: 45)
        let t = TranscriptBuilder.build(me: (bleed + mine).sorted { $0.start < $1.start }, them: call, engine: "test", levels: l)
        #expect(t.lines.filter { $0.side == .me }.map(\.text) == ["sounds good to me"])
        #expect(t.removedEcho.flatMap(\.words).count == bleed.count)
        #expect(t.removedEcho.map(\.start) == t.removedEcho.map(\.start).sorted())
    }
}
