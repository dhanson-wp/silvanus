import Foundation
import Testing
@testable import SilvanusKit

@Suite("Notes sync")
struct NotesSyncTests {
    // MARK: Text changes

    @Test("A change between two texts is the smallest middle that differs")
    func changeIsTheMiddle() {
        let c = TextChange.between("Agenda\n- Scope\n", "Agenda\n- Scope and dates\n")
        #expect(c.range == 14..<14)
        #expect(c.replacement == " and dates")
        #expect(TextChange.between("same", "same").isEmpty)
        let removed = TextChange.between("one two three", "one three")
        #expect(removed.range == 5..<9) // "wo t": the shared start runs through "one t"
        #expect(removed.replacement == "")
    }

    @Test("Changes count UTF-16 units and never split a surrogate pair")
    func changeCountsUTF16() {
        // "😀" is two UTF-16 units; the two faces share their first unit.
        let c = TextChange.between("a😀b", "a😃b")
        #expect(c.range == 1..<3)
        #expect(c.replacement == "😃")
        let applied = (("a😀b" as NSString).replacingCharacters(in: NSRange(location: 1, length: 2), with: c.replacement))
        #expect(applied == "a😃b")
    }

    @Test("A caret before the change stays, after it moves with the text, inside it goes to the change's end")
    func caretFollowsTheText() {
        let c = TextChange.between("Agenda\n- Scope\n", "Agenda\n- Scope and dates\n")
        #expect(c.caret(3) == 3)
        #expect(c.caret(14) == 14)
        #expect(c.caret(15) == 25)
        let removed = TextChange.between("one two three", "one three")
        #expect(removed.caret(6) == 5)
        #expect(removed.caret(13) == 9)
    }

    // MARK: Disk changes

    @Test("A disk change equal to the last save is our own write and is ignored")
    func ownWriteIgnored() {
        var sync = NotesSync(loaded: "Agenda\n")
        sync.saved("Agenda\n- Scope\n")
        #expect(sync.diskChanged(to: "Agenda\n- Scope\n", editor: "Agenda\n- Scope\n", editorDirty: false) == .none)
    }

    @Test("Another app's change reloads when the editor has nothing unsaved")
    func externalChangeReloads() {
        var sync = NotesSync(loaded: "Agenda\n")
        #expect(sync.diskChanged(to: "Agenda\n- Budget\n", editor: "Agenda\n", editorDirty: false) == .show("Agenda\n- Budget\n"))
        // The reloaded text now counts as saved: the same change again is ignored.
        #expect(sync.lastSaved == "Agenda\n- Budget\n")
        #expect(sync.diskChanged(to: "Agenda\n- Budget\n", editor: "Agenda\n- Budget\n", editorDirty: false) == .none)
    }

    @Test("Unsaved typing and a disk change on other lines merge")
    func unsavedTypingMerges() {
        var sync = NotesSync(loaded: "Agenda\n- Scope\n")
        let action = sync.diskChanged(to: "From the phone\nAgenda\n- Scope\n", editor: "Agenda\n- Scope\n- Dates\n", editorDirty: true)
        #expect(action == .merged("From the phone\nAgenda\n- Scope\n- Dates\n"))
        #expect(sync.lastSaved == "From the phone\nAgenda\n- Scope\n")
    }

    @Test("Unsaved typing and a disk change on the same line conflict; the disk text is handed back")
    func unsavedTypingConflicts() {
        var sync = NotesSync(loaded: "Agenda\n- Scope\n")
        let action = sync.diskChanged(to: "Agenda\n- Scope and budget\n", editor: "Agenda\n- Scope and dates\n", editorDirty: true)
        #expect(action == .conflict(theirs: "Agenda\n- Scope and budget\n"))
    }

    @Test("A disk change that already matches the editor only updates the saved text")
    func matchingDiskChange() {
        var sync = NotesSync(loaded: "Agenda\n")
        #expect(sync.diskChanged(to: "Same\n", editor: "Same\n", editorDirty: false) == .none)
        #expect(sync.lastSaved == "Same\n")
    }

    @Test("A missing file is not a change")
    func missingFileIgnored() {
        var sync = NotesSync(loaded: "Agenda\n")
        #expect(sync.diskChanged(to: nil, editor: "Agenda\n", editorDirty: false) == .none)
        #expect(sync.diskChanged(to: nil, editor: "Agenda\n", editorDirty: true) == .none)
        #expect(sync.lastSaved == "Agenda\n")
    }

    @Test("An emptied file is a change, shown like any other")
    func emptiedFileIsShown() {
        var sync = NotesSync(loaded: "Agenda\n")
        #expect(sync.diskChanged(to: "", editor: "Agenda\n", editorDirty: false) == .show(""))
    }
}

@Suite("Three-way merge")
struct TextMergeTests {
    @Test("Edits on different lines both land")
    func nonOverlappingMerge() {
        let base = "# Weekly sync\n- On track\n- Budget\n"
        let r = TextMerge.threeWay(base: base, ours: "# Weekly sync\n- On track\n- Budget\n- Hiring\n",
                                   theirs: "# Weekly sync\nFrom the phone\n- On track\n- Budget\n")
        #expect(!r.conflict)
        #expect(r.merged == "# Weekly sync\nFrom the phone\n- On track\n- Budget\n- Hiring\n")
    }

    @Test("Edits to the same line conflict and keep ours")
    func overlappingConflicts() {
        let base = "# Weekly sync\n- On track\n"
        let r = TextMerge.threeWay(base: base, ours: "# Weekly sync\n- On track, mostly\n",
                                   theirs: "# Weekly sync\n- Slipping\n")
        #expect(r.conflict)
        #expect(r.merged == "# Weekly sync\n- On track, mostly\n")
    }

    @Test("Both sides inserting at the same spot conflict")
    func sameSpotInsertConflicts() {
        let r = TextMerge.threeWay(base: "a\nb\n", ours: "a\nx\nb\n", theirs: "a\ny\nb\n")
        #expect(r.conflict)
    }

    @Test("The same edit on both sides merges cleanly")
    func identicalEditsMerge() {
        let edit = "# Weekly sync\n- On track\n- Budget\n"
        let r = TextMerge.threeWay(base: "# Weekly sync\n- On track\n", ours: edit, theirs: edit)
        #expect(!r.conflict && r.merged == edit)
    }

    @Test("One side unchanged takes the other")
    func oneSideUnchanged() {
        let r = TextMerge.threeWay(base: "a\n", ours: "a\n", theirs: "a\nb\n")
        #expect(!r.conflict && r.merged == "a\nb\n")
    }

    @Test("An empty base: two different texts conflict, the same text merges")
    func emptyBase() {
        #expect(TextMerge.threeWay(base: "", ours: "Mine\n", theirs: "Theirs\n").conflict)
        let same = TextMerge.threeWay(base: "", ours: "Both\n", theirs: "Both\n")
        #expect(!same.conflict && same.merged == "Both\n")
        let theirsOnly = TextMerge.threeWay(base: "", ours: "", theirs: "Theirs\n")
        #expect(!theirsOnly.conflict && theirsOnly.merged == "Theirs\n")
    }

    @Test("A last line without a newline merges")
    func lastLineWithoutNewline() {
        let r = TextMerge.threeWay(base: "a\nb", ours: "a\nb\nc", theirs: "z\na\nb")
        #expect(!r.conflict && r.merged == "z\na\nb\nc")
    }
}
