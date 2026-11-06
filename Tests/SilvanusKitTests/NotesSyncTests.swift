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
        #expect(sync.diskChanged(to: "Agenda\n- Scope\n", editor: "Agenda\n- Scope\n", editorDirty: false) == nil)
    }

    @Test("Another app's change reloads when the editor has nothing unsaved")
    func externalChangeReloads() {
        var sync = NotesSync(loaded: "Agenda\n")
        #expect(sync.diskChanged(to: "Agenda\n- Budget\n", editor: "Agenda\n", editorDirty: false) == "Agenda\n- Budget\n")
        // The reloaded text now counts as saved: the same change again is ignored.
        #expect(sync.lastSaved == "Agenda\n- Budget\n")
        #expect(sync.diskChanged(to: "Agenda\n- Budget\n", editor: "Agenda\n- Budget\n", editorDirty: false) == nil)
    }

    @Test("Unsaved typing wins over a disk change; it saves over it next")
    func unsavedTypingWins() {
        var sync = NotesSync(loaded: "Agenda\n")
        #expect(sync.diskChanged(to: "Other\n", editor: "Agenda\nmore", editorDirty: true) == nil)
    }

    @Test("A disk change that already matches the editor only updates the saved text")
    func matchingDiskChange() {
        var sync = NotesSync(loaded: "Agenda\n")
        #expect(sync.diskChanged(to: "Same\n", editor: "Same\n", editorDirty: false) == nil)
        #expect(sync.lastSaved == "Same\n")
    }

    @Test("A missing file is not a change")
    func missingFileIgnored() {
        var sync = NotesSync(loaded: "Agenda\n")
        #expect(sync.diskChanged(to: nil, editor: "Agenda\n", editorDirty: false) == nil)
    }
}
