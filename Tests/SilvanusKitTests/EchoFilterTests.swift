import Foundation
import Testing
@testable import SilvanusKit

private func line(_ side: Side, _ text: String, from start: TimeInterval) -> TranscriptLine {
    TranscriptLine(side: side, words: testWords(text, from: start))
}

@Test("A mic line equal to a call line 2 seconds later is echo")
func fullRepeatIsEcho() {
    let them = [line(.them, "we should ship the new editor on thursday", from: 12)]
    let mic = line(.me, "we should ship the new editor on thursday", from: 10)
    #expect(TranscriptBuilder.isEcho(mic, them: them))
}

@Test("Exactly half the word pairs matching is echo")
func halfPairsIsEcho() {
    // Mic pairs: aa bb, bb cc, cc dd, dd ee (4). The call shares the first two.
    let them = [line(.them, "aa bb cc", from: 10)]
    let mic = line(.me, "aa bb cc dd ee", from: 10)
    #expect(TranscriptBuilder.isEcho(mic, them: them))
}

@Test("Fewer than half the word pairs matching is kept")
func belowHalfIsKept() {
    // Mic has 5 pairs; the call shares 2 of them (40%).
    let them = [line(.them, "aa bb cc", from: 10)]
    let mic = line(.me, "aa bb cc xx yy zz", from: 10)
    #expect(!TranscriptBuilder.isEcho(mic, them: them))
}

@Test("The same words 7 seconds away are kept")
func outsideWindowIsKept() {
    let them = [line(.them, "we should ship it on thursday", from: 10)]
    let mic = TranscriptLine(side: .me, words: testWords("we should ship it on thursday", from: them[0].end + 7))
    #expect(!TranscriptBuilder.isEcho(mic, them: them))
}

private func timed(_ side: Side, _ text: String, start: TimeInterval, end: TimeInterval) -> TranscriptLine {
    let w = text.split(separator: " ").map(String.init)
    return TranscriptLine(side: side, words: [Word(text: w[0], start: start, end: start + 0.5)]
        + w.dropFirst().dropLast().map { Word(text: $0, start: start, end: start) }
        + [Word(text: w.last!, start: end - 0.5, end: end)])
}

@Test("A call line exactly 6 seconds away still counts")
func exactlySixSecondsIsEcho() {
    let text = "we should ship it on thursday"
    // Call line ends at 12.0; mic line starts at 18.0.
    let before = timed(.them, text, start: 10, end: 12)
    #expect(TranscriptBuilder.isEcho(timed(.me, text, start: 18, end: 20), them: [before]))
    #expect(!TranscriptBuilder.isEcho(timed(.me, text, start: 18.5, end: 20), them: [before]))
    // Mic line ends at 20.0; call line starts at 26.0 (exactly mic.end + 6).
    let mic = timed(.me, text, start: 18, end: 20)
    #expect(TranscriptBuilder.isEcho(mic, them: [timed(.them, text, start: 26, end: 28)]))
    #expect(!TranscriptBuilder.isEcho(mic, them: [timed(.them, text, start: 26.5, end: 28)]))
}

@Test("A mic line sharing only a common phrase with the call is kept")
func shortCommonPhraseIsKept() {
    let them = [line(.them, "and you know the budget is fixed", from: 10)]
    let mic = line(.me, "honestly you know I would rather wait today", from: 11)
    #expect(!TranscriptBuilder.isEcho(mic, them: them))
}

@Test("A one-word mic line has no pairs and is kept")
func singleWordLineIsKept() {
    let them = [line(.them, "yes", from: 10)]
    let mic = line(.me, "yes", from: 10)
    #expect(!TranscriptBuilder.isEcho(mic, them: them))
}

@Test("Punctuation and case are ignored")
func punctuationAndCaseIgnored() {
    let them = [line(.them, "hello there", from: 10)]
    let mic = line(.me, "Hello, there!", from: 10)
    #expect(TranscriptBuilder.isEcho(mic, them: them))
}

@Test("Build records removed lines and sorts what is kept by start")
func buildSortsAndRecordsRemoved() {
    let them = testWords("priya says the launch moves to friday", from: 20)
        + testWords("jordan will update the plan today", from: 40)
    let bleed = testWords("the launch moves to friday", from: 21)
    let early = testWords("morning everyone shall we begin", from: 2)
    let t = TranscriptBuilder.build(me: early + bleed, them: them, engine: "test")
    #expect(t.removedEcho.map(\.text) == ["the launch moves to friday"])
    #expect(t.lines.map(\.start) == t.lines.map(\.start).sorted())
    #expect(t.lines.first?.text == "morning everyone shall we begin")
    #expect(t.lines.count == 3)
    #expect(t.engine == "test")
}

@Test("Hours show once a transcript passes one hour")
func markdownPastAnHour() {
    let t = Transcript(lines: [line(.me, "late", from: 3725)], engine: "test")
    #expect(t.markdown(me: "Sam Rivera") == "[1:02:05] **Sam Rivera:** late")
}

@Test("At the same start time my line comes before theirs")
func buildOrdersMeBeforeThemAtSameStart() {
    let them = testWords("completely different words here", from: 100)
    let mine = testWords("nothing alike appears now", from: 100)
    let t = TranscriptBuilder.build(me: mine, them: them, engine: "test")
    #expect(t.lines.map(\.side) == [.me, .them])
}
