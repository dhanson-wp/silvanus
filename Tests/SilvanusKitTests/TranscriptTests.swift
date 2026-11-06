import Foundation
import Testing
@testable import SilvanusKit

func testWords(_ text: String, from start: TimeInterval, step: TimeInterval = 0.4) -> [Word] {
    text.split(separator: " ").enumerated().map { i, w in
        Word(text: String(w), start: start + Double(i) * step, end: start + Double(i) * step + 0.3)
    }
}

@Test("Clock formats times", arguments: [(0.0, "00:00"), (252.9, "04:12"), (3725, "1:02:05")])
func clock(_ seconds: TimeInterval, text: String) {
    #expect(Clock.text(seconds) == text)
}

@Test("Word pieces join into words")
func wordPieces() {
    let tokens: [(text: String, start: TimeInterval, end: TimeInterval, confidence: Float)] = [
        ("▁Lo", 0.0, 0.2, 0.9), ("cus", 0.2, 0.4, 0.6), ("▁Mag", 0.5, 0.7, 0.95), (".", 0.7, 0.75, 0.99),
    ]
    let w = TranscriptBuilder.words(fromTokens: tokens, offset: 10)
    #expect(w.map(\.text) == ["Locus", "Mag."])
    #expect(w[0].start == 10 && w[0].end == 10.4)
    #expect(w[0].confidence == 0.6)
    let digits: [(text: String, start: TimeInterval, end: TimeInterval, confidence: Float)] = [
        ("▁in", 0, 0.2, 1), ("27", 0.2, 0.4, 1), ("▁min", 0.5, 0.6, 1), ("utes", 0.6, 0.7, 1),
    ]
    #expect(TranscriptBuilder.words(fromTokens: digits).map(\.text) == ["in", "27", "minutes"])
}

@Test("A pause starts a new line")
func linesSplitOnPause() {
    let w = testWords("one two three", from: 0) + testWords("four five", from: 5)
    let lines = TranscriptBuilder.lines(w, side: .me)
    #expect(lines.map(\.text) == ["one two three", "four five"])
}

@Test("Mic lines that repeat the call audio are removed, my own lines stay")
func echoFilter() {
    let them = testWords("so the hero would be the svg and the patterns are blocks", from: 10)
    let bleed = testWords("the hero would be the svg and the patterns", from: 10.2)
    let mine = testWords("that works can we keep it small", from: 20)
    let t = TranscriptBuilder.build(me: bleed + mine, them: them, engine: "test")
    #expect(t.removedEcho.map(\.text) == ["the hero would be the svg and the patterns"])
    #expect(t.lines.map(\.side) == [.them, .me])
    #expect(t.lines.last?.text == "that works can we keep it small")
}

@Test("The same words far apart in time are not echo")
func echoNeedsNearbyTime() {
    let them = testWords("we should ship it on thursday", from: 10)
    let mine = testWords("we should ship it on thursday", from: 300)
    #expect(TranscriptBuilder.build(me: mine, them: them, engine: "test").removedEcho.isEmpty)
}

@Test("Transcript Markdown names each side")
func transcriptMarkdown() {
    let t = Transcript(lines: [TranscriptLine(side: .me, words: testWords("hi there", from: 3)),
                               TranscriptLine(side: .them, words: testWords("hello", from: 65))], engine: "test")
    #expect(t.markdown(me: "Sam Rivera") == "[00:03] **Sam Rivera:** hi there\n\n[01:05] **Them:** hello")
}
