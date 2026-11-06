import Foundation
import Testing
@testable import SilvanusKit

@Suite("Markdown style")
struct MarkdownStyleTests {
    // MARK: Block kinds

    @Test("Each block marker is recognized, with its marker range")
    func blockKinds() {
        let cases: [(String, MarkdownStyle.BlockKind, Range<Int>)] = [
            ("# Acme kickoff", .heading(level: 1), 0..<2),
            ("## Agenda", .heading(level: 2), 0..<3),
            ("### Notes", .heading(level: 3), 0..<4),
            ("- Budget review", .bullet, 0..<2),
            ("* Budget review", .bullet, 0..<2),
            ("1. Intros", .numbered, 0..<3),
            ("12. Wrap up", .numbered, 0..<4),
            ("[ ] Send the deck", .task(done: false), 0..<4),
            ("- [ ] Send the deck", .task(done: false), 0..<6),
            ("> Priya: ship it", .quote, 0..<2),
            ("Plain words here", .paragraph, 0..<0),
        ]
        for (line, kind, marker) in cases {
            let block = MarkdownStyle.block(Substring(line))
            #expect(MarkdownStyle.blockKind(Substring(line)) == kind, "\(line)")
            #expect(block.marker == marker, "\(line)")
        }
    }

    @Test("[x] is a done task, in either case")
    func doneTask() {
        #expect(MarkdownStyle.blockKind("[x] Book the room") == .task(done: true))
        #expect(MarkdownStyle.blockKind("[X] Book the room") == .task(done: true))
        #expect(MarkdownStyle.blockKind("- [x] Book the room") == .task(done: true))
        let block = MarkdownStyle.block("[x] Book the room")
        #expect(block.box == 0..<3)
        #expect(block.content == 4..<17)
    }

    @Test("Markers need their trailing space")
    func markersNeedSpace() {
        #expect(MarkdownStyle.blockKind("#hashtag") == .paragraph)
        #expect(MarkdownStyle.blockKind("-dash") == .paragraph)
        #expect(MarkdownStyle.blockKind("1.5 million") == .paragraph)
        #expect(MarkdownStyle.blockKind("####### seven") == .paragraph)
        #expect(MarkdownStyle.blockKind("[ ]nothing") == .paragraph)
    }

    @Test("An empty item is still that kind, so Return can end the list")
    func emptyItems() {
        #expect(MarkdownStyle.blockKind("- ") == .bullet)
        #expect(MarkdownStyle.blockKind("[ ] ") == .task(done: false))
        #expect(MarkdownStyle.blockKind("3. ") == .numbered)
        #expect(MarkdownStyle.blockKind(">") == .quote)
        #expect(MarkdownStyle.block("- ").content.isEmpty)
    }

    @Test("Indented list items keep their indent apart from the marker")
    func indented() {
        let block = MarkdownStyle.block("\t- Nested")
        #expect(block.kind == .bullet)
        #expect(block.indent == 0..<1)
        #expect(block.marker == 1..<3)
        #expect(block.content == 3..<9)
    }

    // MARK: Inline spans

    @Test("Bold, italic, and code give three spans with their ranges")
    func threeSpans() {
        let spans = MarkdownStyle.inlineSpans("**a** and _b_ and `c`")
        #expect(spans.count == 3)
        guard spans.count == 3 else { return }
        #expect(spans[0].kind == .bold)
        #expect(spans[0].range == 0..<5)
        #expect(spans[0].content == 2..<3)
        #expect(spans[0].markers == [0..<2, 3..<5])
        #expect(spans[1].kind == .italic)
        #expect(spans[1].range == 10..<13)
        #expect(spans[1].content == 11..<12)
        #expect(spans[1].markers == [10..<11, 12..<13])
        #expect(spans[2].kind == .code)
        #expect(spans[2].range == 18..<21)
        #expect(spans[2].content == 19..<20)
        #expect(spans[2].markers == [18..<19, 20..<21])
    }

    @Test("An unclosed marker is no span")
    func unclosed() {
        #expect(MarkdownStyle.inlineSpans("**a").isEmpty)
        #expect(MarkdownStyle.inlineSpans("_a").isEmpty)
        #expect(MarkdownStyle.inlineSpans("`a").isEmpty)
        #expect(MarkdownStyle.inlineSpans("****").isEmpty)
    }

    @Test("Underscores inside words are not italic")
    func snakeCase() {
        #expect(MarkdownStyle.inlineSpans("call user_id and team_name").isEmpty)
    }

    @Test("Nothing is styled inside code")
    func codeWins() {
        let spans = MarkdownStyle.inlineSpans("`**not bold**`")
        #expect(spans.map(\.kind) == [.code])
    }

    @Test("Ranges count UTF-16, the way the text view does")
    func utf16() {
        let spans = MarkdownStyle.inlineSpans("🎉 **yes**")
        #expect(spans.first?.range == 3..<10)
    }

    // MARK: Runs and round trip

    static let fixture = """
    # Acme kickoff
    ## Agenda
    1. Intros from Sam Rivera
    2. Timeline with Priya Natarajan
    - Budget is **fixed** at _last year's_ number
    \t- Nested point with `code`
    [ ] Send the deck
    [x] Book the room
    - [ ] Follow up on the contract
    > Priya: we ship in March.

    Plain paragraph with **bold**, _italic_, and `code` 🎉.
    Unclosed **bold and _italic stay plain.
    """

    @Test("Styling runs leave the string exactly as written")
    func roundTrip() {
        let runs = MarkdownStyle.runs(in: Self.fixture)
        let styled = NSMutableAttributedString(string: Self.fixture)
        let key = NSAttributedString.Key("silvanus.role")
        let length = (Self.fixture as NSString).length
        for run in runs {
            #expect(run.range.lowerBound >= 0 && run.range.upperBound <= length)
            styled.addAttribute(key, value: String(describing: run.role),
                                range: NSRange(location: run.range.lowerBound, length: run.range.count))
        }
        #expect(styled.string == Self.fixture)
        #expect(Array(styled.string.utf8) == Array(Self.fixture.utf8))
        // Every construct produced a run.
        let roles = Set(runs.map { String(describing: $0.role) })
        for role in ["heading(level: 1)", "heading(level: 2)", "marker", "bold", "italic", "code", "quote", "done"] {
            #expect(roles.contains(role), "missing \(role)")
        }
    }

    @Test("Runs of one line land at that line's offset")
    func lineRunsOffset() {
        let runs = MarkdownStyle.lineRuns("# Hi", offset: 10)
        #expect(runs.contains { $0.role == .marker && $0.range == 10..<12 })
        #expect(runs.contains { $0.role == .heading(level: 1) && $0.range == 10..<14 })
    }
}

@Suite("Markdown block kinds")
struct MarkdownBlockKindTests {
    @Test("List items and heading levels are named on the kind")
    func kindHelpers() {
        #expect(MarkdownStyle.BlockKind.bullet.isListItem)
        #expect(MarkdownStyle.BlockKind.numbered.isListItem)
        #expect(MarkdownStyle.BlockKind.task(done: true).isListItem)
        #expect(!MarkdownStyle.BlockKind.quote.isListItem)
        #expect(!MarkdownStyle.BlockKind.heading(level: 1).isListItem)
        #expect(MarkdownStyle.BlockKind.heading(level: 2).headingLevel == 2)
        #expect(MarkdownStyle.BlockKind.paragraph.headingLevel == nil)
    }
}
