import Foundation
import Testing
@testable import SilvanusKit

private func line(_ side: Side, _ text: String, at start: TimeInterval, confidence: Float = 1) -> TranscriptLine {
    let words = text.split(separator: " ").enumerated().map { i, w in
        Word(text: String(w), start: start + Double(i) * 0.4, end: start + Double(i) * 0.4 + 0.3, confidence: confidence)
    }
    return TranscriptLine(side: side, words: words)
}

private let kickoff = Transcript(lines: [
    line(.me, "Thanks for joining.", at: 0),
    line(.me, "Let's start with scope.", at: 3),
    line(.them, "Sounds good.", at: 6),
    line(.them, "We have two questions.", at: 9),
    line(.me, "Go ahead.", at: 14),
], engine: "test", processedAt: Date(timeIntervalSince1970: 0))

@Test("Consecutive lines from one side share one speaker label")
func blocksMergeSameSide() {
    let blocks = TranscriptLayout.blocks(kickoff, me: "Sam Rivera")
    #expect(blocks.map(\.speaker) == ["Sam Rivera", "Them", "Sam Rivera"])
    #expect(blocks.map(\.side) == [.me, .them, .me])
    #expect(blocks[0].text == "Thanks for joining. Let's start with scope.")
    #expect(blocks[1].text == "Sounds good. We have two questions.")
    #expect(blocks.map(\.start) == [0, 6, 14])
}

@Test("Each block knows where its words start in the whole transcript")
func blocksCountWords() {
    let blocks = TranscriptLayout.blocks(kickoff, me: "Sam Rivera")
    #expect(blocks.map(\.firstWord) == [0, 7, 13])
    #expect(blocks.map(\.id) == [0, 1, 2])
    let all = TranscriptLayout.words(blocks)
    #expect(all.count == 15)
    #expect(all[7].text == "Sounds")
}

@Test("A named call speaker replaces Them")
func blocksUseSpeakerName() {
    let blocks = TranscriptLayout.blocks(kickoff, me: "Me", them: "Priya Natarajan")
    #expect(blocks.map(\.speaker) == ["Me", "Priya Natarajan", "Me"])
}

@Test("An empty transcript, or lines with no words, has no blocks")
func blocksEmpty() {
    let empty = Transcript(lines: [], engine: "test")
    #expect(TranscriptLayout.blocks(empty, me: "Me").isEmpty)
    let blank = Transcript(lines: [TranscriptLine(side: .me, words: [])], engine: "test")
    #expect(TranscriptLayout.blocks(blank, me: "Me").isEmpty)
}

@Test("Words under 0.6 confidence are low", arguments: [(Float(0.59), true), (0.6, false), (1, false), (0, true)])
func lowConfidence(_ confidence: Float, low: Bool) {
    #expect(TranscriptLayout.isLowConfidence(Word(text: "x", start: 0, end: 1, confidence: confidence)) == low)
}

@Test("The length is the last word's end")
func duration() {
    #expect(abs(TranscriptLayout.duration(kickoff) - 14.7) < 0.000_1)
    #expect(TranscriptLayout.duration(Transcript(lines: [], engine: "test")) == 0)
}

@Test("A 20,000-word transcript lays out quickly")
func blocksAreFast() {
    var lines: [TranscriptLine] = []
    for i in 0..<1_000 {
        lines.append(line(i % 3 == 2 ? .me : .them, Array(repeating: "word", count: 20).joined(separator: " "), at: Double(i) * 9))
    }
    let t = Transcript(lines: lines, engine: "test")
    let clock = ContinuousClock()
    let elapsed = clock.measure { _ = TranscriptLayout.blocks(t, me: "Me") }
    #expect(TranscriptLayout.words(TranscriptLayout.blocks(t, me: "Me")).count == 20_000)
    #expect(elapsed < .milliseconds(100))
}

@Test("A time picks the word being said then, or the last one before it")
func wordAtTime() {
    let words = TranscriptLayout.words(TranscriptLayout.blocks(kickoff, me: "Me"))
    #expect(TranscriptLayout.wordIndex(at: 0, in: words) == 0)
    #expect(TranscriptLayout.wordIndex(at: 0.5, in: words) == 1)
    #expect(TranscriptLayout.wordIndex(at: 6, in: words) == 7)
    #expect(TranscriptLayout.wordIndex(at: 5, in: words) == 6)
    #expect(TranscriptLayout.wordIndex(at: 999, in: words) == 14)
    #expect(TranscriptLayout.wordIndex(at: -1, in: words) == nil)
    #expect(TranscriptLayout.wordIndex(at: 1, in: []) == nil)
}

@Test("Speech levels: the share of each slice of time that has words in it")
func activityLevels() {
    // Words cover 0 to 1 and 3 to 4 of a 4-second transcript.
    let t = Transcript(lines: [
        TranscriptLine(side: .me, words: [Word(text: "a", start: 0, end: 1)]),
        TranscriptLine(side: .them, words: [Word(text: "b", start: 3, end: 4)]),
    ], engine: "test")
    #expect(TranscriptLayout.activity(t, slices: 4) == [1, 0, 0, 1])
    #expect(TranscriptLayout.activity(t, slices: 8) == [1, 1, 0, 0, 0, 0, 1, 1])
    #expect(TranscriptLayout.activity(t, slices: 2) == [0.5, 0.5])
    #expect(TranscriptLayout.activity(Transcript(lines: [], engine: "test"), slices: 3) == [0, 0, 0])
}

@Test("Speaker names: the meeting's own names win, then the defaults")
func speakerNames() {
    let start = Date(timeIntervalSince1970: 0)
    let unmapped = SpeakerNames.resolve(info: MeetingInfo(title: "Acme kickoff", start: start), defaultMe: "Me")
    #expect(unmapped.me == "Me" && unmapped.them == "Them")
    let mapped = SpeakerNames.resolve(info: MeetingInfo(title: "Acme kickoff", start: start,
                                                        speakers: ["me": "Sam Rivera", "them": "Priya Natarajan"]),
                                      defaultMe: "Me")
    #expect(mapped.me == "Sam Rivera" && mapped.them == "Priya Natarajan")
    let blank = SpeakerNames.resolve(info: MeetingInfo(title: "Acme kickoff", start: start, speakers: ["me": " ", "them": ""]),
                                     defaultMe: "Jordan Lee")
    #expect(blank.me == "Jordan Lee" && blank.them == "Them")
}

@Test("Times read aloud", arguments: [(0.0, "0 seconds"), (1, "1 second"), (14.9, "14 seconds"), (60, "1 minute"),
                                      (65, "1 minute 5 seconds"), (125, "2 minutes 5 seconds"), (3725, "1 hour 2 minutes 5 seconds"),
                                      (7200, "2 hours")])
func spokenTime(_ seconds: TimeInterval, text: String) {
    #expect(Clock.spoken(seconds) == text)
}

@Test("Times read aloud to the minute", arguments: [(0.0, "less than a minute"), (59.9, "less than a minute"), (60, "1 minute"),
                                                     (754, "12 minutes"), (3600, "1 hour"), (3900, "1 hour 5 minutes"),
                                                     (7199, "1 hour 59 minutes")])
func spokenMinutes(_ seconds: TimeInterval, text: String) {
    #expect(Clock.spokenMinutes(seconds) == text)
}

@Test("Each word's run, with its trailing space, links to its index in the whole transcript")
func paragraphLinks() {
    let words = ["Café", "is", "open", "🎉", "today"].enumerated().map { i, w in
        Word(text: w, start: Double(i), end: Double(i) + 0.5, confidence: i == 0 ? 0.3 : 1)
    }
    let block = TranscriptLayout.Block(id: 2, side: .them, speaker: "Them", words: words, firstWord: 40)
    var styled: [Int] = []
    let text = TranscriptLayout.paragraph(block) { index, _, _ in styled.append(index) }
    #expect(String(text.characters) == "Café is open 🎉 today")
    #expect(styled == [40, 41, 42, 43, 44])
    var linked: [(String, Int)] = []
    for run in text.runs {
        guard let url = run.link, let index = TranscriptLayout.wordIndex(link: url) else { continue }
        let piece = String(text[run.range].characters)
        if let last = linked.last, last.1 == index { linked[linked.count - 1].0 += piece } else { linked.append((piece, index)) }
    }
    #expect(linked.map(\.0) == ["Café ", "is ", "open ", "🎉 ", "today"])
    #expect(linked.map(\.1) == [40, 41, 42, 43, 44])
    #expect(TranscriptLayout.wordIndex(link: URL(string: "https://example.com/3")!) == nil)
}
