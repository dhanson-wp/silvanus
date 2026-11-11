import Foundation
import Testing
@testable import SilvanusKit

@Suite("To-dos") struct TodosTests {
    @Test("The answer's list items become checkboxes; other lines and repeats are dropped")
    func parseAnswer() {
        let answer = """
            Here are the to-dos:
            - [ ] Sam Rivera: send the project plan by Friday
            * Priya Shah: book the review room
            - [x] Sam Rivera: Send the project plan by Friday.
            Thanks!
            """
        #expect(Todos.parse(answer) == [
            "- [ ] Sam Rivera: send the project plan by Friday",
            "- [ ] Priya Shah: book the review room",
        ])
    }

    @Test("NONE, or an answer with no list, is no to-dos")
    func parseNone() {
        #expect(Todos.parse("NONE").isEmpty)
        #expect(Todos.parse("- NONE").isEmpty)
        #expect(Todos.parse("There were no commitments in this call.").isEmpty)
    }

    @Test("The request carries who is reading, their notes, and the transcript")
    func request() {
        let text = Todos.request(transcript: "[00:01] **Sam Rivera:** I'll send it.\n", notes: "Plan due Friday\n", me: "Sam Rivera")
        #expect(text.contains("The person reading this list is Sam Rivera."))
        #expect(text.contains("Plan due Friday"))
        #expect(text.hasSuffix("**Sam Rivera:** I'll send it."))
        #expect(!Todos.request(transcript: "x", notes: "  \n").contains("own notes"))
    }

    @Test("A first list, or one I never touched, is replaced by the new answer")
    func untouchedListIsReplaced() {
        let old = "- [ ] Sam: send the plan\n"
        #expect(Todos.merge(existing: "", written: "", generated: ["- [ ] Sam: send the plan"]) == old)
        #expect(Todos.merge(existing: old, written: old, generated: ["- [ ] Priya: book the room"]) == "- [ ] Priya: book the room\n")
    }

    @Test("With no to-dos the file says so, and a later answer replaces that line")
    func noneLine() {
        #expect(Todos.merge(existing: "", written: "", generated: []) == Todos.none + "\n")
        #expect(Todos.merge(existing: Todos.none + "\n", written: Todos.none + "\n", generated: ["- [ ] Sam: send the plan"])
            == "- [ ] Sam: send the plan\n")
    }

    @Test("A list I ticked, edited, or added to keeps every line and gains only new to-dos")
    func changedListIsKept() {
        let written = "- [ ] Sam: send the plan\n- [ ] Priya: book the room\n"
        let mine = "- [x] Sam: send the plan\n- [ ] Call the venue myself\n"
        let merged = Todos.merge(existing: mine, written: written,
                                 generated: ["- [ ] Sam: send the plan", "- [ ] Priya: book the room", "- [ ] Jordan: share the deck"])
        // Ticked stays ticked, mine stays, the one I deleted doesn't come back, the new one is added.
        #expect(merged == "- [x] Sam: send the plan\n- [ ] Call the venue myself\n- [ ] Jordan: share the deck\n")
    }

    @Test("A changed list is left alone when the new answer has no to-dos")
    func changedListSurvivesNone() {
        let mine = "- [x] Sam: send the plan\n"
        #expect(Todos.merge(existing: mine, written: "- [ ] Sam: send the plan\n", generated: []) == mine)
    }

    @Test("The page is the heading, the list, then the summary; only the list comes back out")
    func page() {
        let page = TodoPage(summary: "## Overview\nAgreed on scope.\n")
        let text = page.text(todo: "- [ ] Sam: send the plan\n")
        #expect(text == "## To-dos\n- [ ] Sam: send the plan\n\n## Overview\nAgreed on scope.\n")
        #expect(page.todo(in: text) == "- [ ] Sam: send the plan\n")
        #expect(page.todo(in: text.replacingOccurrences(of: "[ ]", with: "[x]")) == "- [x] Sam: send the plan\n")
        #expect(page.lockedPrefix == 10)
        #expect(page.lockedSuffix == ("\n\n## Overview\nAgreed on scope.\n" as NSString).length)
    }

    @Test("With no summary nothing follows the list; an emptied list is empty")
    func pageWithoutSummary() {
        let page = TodoPage(summary: "")
        #expect(page.text(todo: "- [ ] One\n") == "## To-dos\n- [ ] One")
        #expect(page.todo(in: "## To-dos\n- [ ] One\n- [ ] Two") == "- [ ] One\n- [ ] Two\n")
        #expect(page.todo(in: "## To-dos\n") == "")
        #expect(page.todo(in: "To-dos gone") == nil)
    }
}

@Suite("To-do board") struct TodoBoardTests {
    private func meeting(_ id: String, _ todo: String) -> Meeting {
        Meeting(info: MeetingInfo(id: id, title: id.capitalized, start: Date(timeIntervalSince1970: 1_793_975_400)), todo: todo)
    }

    @Test("Only checkbox lines are to-dos, and each remembers its line")
    func items() {
        let items = TodoBoard.items(in: "- [ ] Sam: send the plan\nA plain line\n- [x] Priya: book the room\n", meetingID: "kickoff")
        #expect(items.map(\.text) == ["Sam: send the plan", "Priya: book the room"])
        #expect(items.map(\.done) == [false, true])
        #expect(items.map(\.line) == [0, 2])
        #expect(TodoBoard.items(in: Todos.none + "\n", meetingID: "kickoff").isEmpty)
    }

    @Test("The board lists meetings with something still to do, done ones included in their group")
    func groups() {
        let board = TodoBoard.groups([
            meeting("kickoff", "- [ ] Sam: send the plan\n- [x] Priya: book the room\n"),
            meeting("sync", "- [x] Jordan: share the deck\n"),
            meeting("review", Todos.none + "\n"),
            meeting("notes", ""),
        ])
        #expect(board.map(\.meetingID) == ["kickoff"])
        #expect(board.first?.items.count == 2)
        #expect(board.first?.open == 1)
    }

    @Test("The count is the open to-dos across every meeting")
    func openCount() {
        #expect(TodoBoard.openCount([meeting("a", "- [ ] One\n- [ ] Two\n- [x] Three\n"), meeting("b", "- [ ] Four\n")]) == 3)
    }

    @Test("Ticking changes only that line's box, and unticking puts it back")
    func toggled() {
        let todo = "- [ ] Sam: send the plan\n- [ ] Priya: book the room\n"
        let ticked = TodoBoard.toggled(todo, line: 1)
        #expect(ticked == "- [ ] Sam: send the plan\n- [x] Priya: book the room\n")
        #expect(TodoBoard.toggled(ticked ?? "", line: 1) == todo)
        #expect(TodoBoard.toggled(todo, line: 2) == nil)
        #expect(TodoBoard.toggled("Plain\n", line: 0) == nil)
    }
}
