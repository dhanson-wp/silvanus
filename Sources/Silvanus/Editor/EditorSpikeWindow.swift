import AppKit
import SwiftUI
import SilvanusKit

// The native editor spike (task 7). Not part of the app's UI yet.
//   APP_EDITOR_SPIKE=1 Silvanus   open the spike window with a fictional note
//   APP_EDITOR_SPIKE=1 APP_SNAPSHOT=<dir> APP_STORE=/tmp/... Silvanus
//                                 snapshot it light and dark, caret on a heading and on a plain line
//   APP_EDITOR_CHECK=1 Silvanus   run the editor's bar checks headless, print PASS/FAIL, exit 0 or 1
//   APP_EDITOR_BENCH=1 Silvanus   time 200 keystrokes in a 5,000-line note, print median and p95, exit

struct EditorSpikeView: View {
    @State private var text = EditorSpike.fixture
    var body: some View {
        MarkdownEditor(text: $text) { EditorSpike.textView = $0 }
            .frame(minWidth: 560, minHeight: 480)
    }
}

enum EditorSpike {
    static var env: [String: String] { ProcessInfo.processInfo.environment }
    static var enabled: Bool { env["APP_EDITOR_SPIKE"] == "1" }
    static var window: NSWindow?
    static var textView: NotesTextView?

    /// A fictional meeting with every construct the bar covers.
    static let fixture = """
    # Acme kickoff
    Thursday with Sam Rivera and Priya Natarajan.

    ## Agenda
    1. Intros and roles
    2. Timeline for the **first release**
    3. Budget and _what's fixed_

    ## Notes
    - Priya owns the integration plan
    - Sam shares the `staging` checklist by Friday
    \t- Nested: the checklist lives in the shared folder
    - Launch target is **March**, with _one_ buffer week

    > Priya: we ship the beta before the offsite.

    ### Decisions
    The scope stays as written. Anything new goes to the next round.

    ## To-dos
    [ ] Send the deck to Priya
    [x] Book the room for the review
    - [ ] Draft the `release-notes.md` outline
    - [x] Share the agenda

    Plain closing line, no markers here.
    """

    /// The fixture repeated to `lines` lines, for the benchmark.
    static func bigFixture(lines: Int) -> String {
        let base = fixture.split(separator: "\n", omittingEmptySubsequences: false)
        return (0..<lines).map { String(base[$0 % base.count]) }.joined(separator: "\n")
    }

    // MARK: Spike window

    static func openIfRequested() {
        guard enabled else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Editor spike"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorSpikeView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        Snapshot.runEditorSpikeIfRequested()
    }

    // MARK: Headless runs

    /// Runs the checks or the benchmark when asked; returns the exit code.
    static func runHeadlessIfRequested() -> Int32? {
        setvbuf(stdout, nil, _IOLBF, 0)
        if env["APP_EDITOR_CHECK"] == "1" { var checks = EditorChecks(); return checks.run() }
        if env["APP_EDITOR_BENCH"] == "1" { return bench() }
        return nil
    }

    /// An editor in a borderless window placed off screen, so it lays out and
    /// draws like a real one without showing up. Undo groups are explicit.
    static func offscreenEditor(_ text: String) -> (NSWindow, NotesTextView, UndoManager) {
        let window = UndoWindow(contentRect: NSRect(x: -6000, y: -6000, width: 760, height: 720),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let (scroll, view) = NotesTextView.scrollable()
        scroll.frame = window.contentLayoutRect
        scroll.autoresizingMask = [.width, .height]
        window.contentView = scroll
        view.frame = NSRect(origin: .zero, size: scroll.contentSize)
        window.orderFrontRegardless()
        window.makeFirstResponder(view)
        window.undo.beginUndoGrouping()
        view.load(text)
        window.undo.endUndoGrouping()
        window.undo.removeAllActions()
        return (window, view, window.undo)
    }

    final class UndoWindow: NSWindow {
        let undo: UndoManager = {
            let u = UndoManager()
            u.groupsByEvent = false
            return u
        }()
        override var undoManager: UndoManager? { undo }
        override var canBecomeKey: Bool { true }
    }

    // MARK: Benchmark

    private static func bench() -> Int32 {
        let lines = 5000
        let text = bigFixture(lines: lines)
        let loadStart = CFAbsoluteTimeGetCurrent()
        let (window, view, undo) = offscreenEditor(text)
        view.textLayoutManager?.textViewportLayoutController.layoutViewport()
        let loadMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
        print("BENCH TextKit 2 after setup: \(view.isTextKit2)")
        print("BENCH load and style \(lines) lines: \(fmt(loadMs)) ms")

        // The caret at the end of line 2,500, scrolled into view.
        let ns = view.string as NSString
        var location = 0
        for _ in 0..<(lines / 2) { location = NSMaxRange(ns.lineRange(for: NSRange(location: location, length: 0))) }
        location -= 1
        view.setSelectedRange(NSRange(location: location, length: 0))
        view.scrollRangeToVisible(view.selectedRange())
        view.textLayoutManager?.textViewportLayoutController.layoutViewport()
        view.display()

        let typed = Array("Sam and Priya agreed on the **plan** for _March_. ")
        var insert: [Double] = [], restyle: [Double] = [], layout: [Double] = [], draw: [Double] = [], binding: [Double] = []
        for i in 0..<200 {
            let c = String(typed[i % typed.count])
            undo.beginUndoGrouping()
            let t0 = CFAbsoluteTimeGetCurrent()
            view.insertText(c, replacementRange: view.selectedRange())
            let t1 = CFAbsoluteTimeGetCurrent()
            view.textLayoutManager?.textViewportLayoutController.layoutViewport()
            let t2 = CFAbsoluteTimeGetCurrent()
            view.display()
            let t3 = CFAbsoluteTimeGetCurrent()
            _ = view.string // what the SwiftUI binding copies per keystroke
            let t4 = CFAbsoluteTimeGetCurrent()
            undo.endUndoGrouping()
            insert.append((t1 - t0) * 1000)
            restyle.append(view.styler.lastRestyle * 1000)
            layout.append((t2 - t1) * 1000)
            draw.append((t3 - t2) * 1000)
            binding.append((t4 - t3) * 1000)
        }
        let total = (0..<200).map { insert[$0] + layout[$0] + draw[$0] + binding[$0] }
        print("BENCH 200 inserts at line 2,500 of \(lines) (ms):")
        for (name, values) in [("insertText incl. restyle", insert), ("  restyle alone", restyle),
                               ("viewport layout", layout), ("draw", draw), ("binding copy", binding),
                               ("total per keystroke", total)] {
            print("BENCH   \(name.padding(toLength: 26, withPad: " ", startingAt: 0)) median \(fmt(median(values)))  p95 \(fmt(p95(values)))  max \(fmt(values.max() ?? 0))")
        }
        print("BENCH TextKit 2 after typing: \(view.isTextKit2)")
        window.orderOut(nil)
        return 0
    }

    static func median(_ v: [Double]) -> Double { let s = v.sorted(); return s[s.count / 2] }
    static func p95(_ v: [Double]) -> Double { let s = v.sorted(); return s[Int(Double(s.count - 1) * 0.95)] }
    static func fmt(_ v: Double) -> String { String(format: "%.3f", v) }
}

/// Exercises every item on the editor bar against a real NotesTextView and
/// prints PASS or FAIL for each.
@MainActor
struct EditorChecks {
    private var failures = 0
    private var count = 0

    mutating func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name): \(detail())")
    }

    mutating func run() -> Int32 {
        let (window, view, undo) = EditorSpike.offscreenEditor("")
        let style = view.styler.style
        func type(_ s: String) {
            undo.beginUndoGrouping()
            for c in s { view.insertText(String(c), replacementRange: view.selectedRange()) }
            undo.endUndoGrouping()
        }
        func command(_ selector: Selector) {
            undo.beginUndoGrouping()
            view.doCommand(by: selector)
            undo.endUndoGrouping()
        }
        func reset(_ text: String, caret: Int? = nil) {
            view.load(text)
            undo.removeAllActions()
            view.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
        }
        func attr(_ key: NSAttributedString.Key, at i: Int) -> Any? {
            view.textStorage?.attribute(key, at: i, effectiveRange: nil)
        }
        func font(at i: Int) -> NSFont? { attr(.font, at: i) as? NSFont }
        func color(at i: Int) -> NSColor? { attr(.foregroundColor, at: i) as? NSColor }
        func traits(at i: Int) -> NSFontTraitMask { font(at: i).map { NSFontManager.shared.traits(of: $0) } ?? [] }
        let newline = #selector(NSResponder.insertNewline(_:))

        check("TextKit 2 is active after setup", view.isTextKit2)

        // Format as you type.
        reset("")
        type("# Acme kickoff")
        check("# formats a heading as you type", font(at: 3)?.pointSize == style.headingSizes[0], "\(String(describing: font(at: 3)))")
        reset("")
        type("## Agenda")
        check("## gives the H2 size", font(at: 4)?.pointSize == style.headingSizes[1])
        reset("Agenda", caret: 0)
        type("### ")
        check("a marker typed before existing words formats the line", font(at: 5)?.pointSize == style.headingSizes[2],
              "\(view.string.debugDescription) \(String(describing: font(at: 5)))")
        reset("")
        type("Budget **fixed** and _late_ and `code`")
        check("** makes bold as you type", traits(at: 10).contains(.boldFontMask))
        check("_ makes italic as you type", traits(at: 23).contains(.italicFontMask))
        check("` makes code as you type", font(at: 34)?.isFixedPitch == true)
        check("plain words stay plain", !traits(at: 2).contains(.boldFontMask) && font(at: 2)?.pointSize == style.bodySize)
        reset("")
        type("> Priya: ship it")
        check("> styles a quote", color(at: 5) == style.quote)
        reset("")
        type("[x] Book the room")
        check("[x] strikes the task through", attr(.strikethroughStyle, at: 6) as? Int == NSUnderlineStyle.single.rawValue)

        // Markers fade when the caret leaves the line.
        reset("# Title\nplain line", caret: 3)
        check("markers are shown on the caret's line", color(at: 0) == style.markerActive, "\(String(describing: color(at: 0)))")
        view.setSelectedRange(NSRange(location: 12, length: 0))
        check("markers fade when the caret leaves", color(at: 0) == style.markerFaded, "\(String(describing: color(at: 0)))")
        check("fading keeps every character", view.string == "# Title\nplain line")

        // Return, Tab, Shift-Tab.
        reset("- Budget")
        command(newline)
        check("Return continues a bullet list", view.string == "- Budget\n- ", view.string.debugDescription)
        command(newline)
        check("Return on an empty item ends the list", view.string == "- Budget\n", view.string.debugDescription)
        reset("1. Intros")
        command(newline)
        check("Return numbers the next item", view.string == "1. Intros\n2. ", view.string.debugDescription)
        reset("[ ] Send the deck")
        command(newline)
        check("Return continues tasks with an open box", view.string == "[ ] Send the deck\n[ ] ", view.string.debugDescription)
        reset("- [x] Shared")
        command(newline)
        check("Return after a done dash task opens a new one", view.string == "- [x] Shared\n- [ ] ", view.string.debugDescription)
        reset("> Quote")
        command(newline)
        check("Return continues a quote", view.string == "> Quote\n> ", view.string.debugDescription)
        reset("# Heading")
        command(newline)
        check("Return after a heading starts a plain line", view.string == "# Heading\n", view.string.debugDescription)
        reset("- One\n- Two")
        command(#selector(NSResponder.insertTab(_:)))
        check("Tab indents a list item", view.string == "- One\n\t- Two", view.string.debugDescription)
        check("Tab keeps the caret at the end", view.selectedRange().location == (view.string as NSString).length)
        command(#selector(NSResponder.insertBacktab(_:)))
        check("Shift-Tab outdents it", view.string == "- One\n- Two", view.string.debugDescription)
        reset("Plain")
        command(#selector(NSResponder.insertTab(_:)))
        check("Tab on plain text types a tab", view.string == "Plain\t", view.string.debugDescription)

        // Task boxes.
        reset("[ ] Send the deck\nnext")
        undo.beginUndoGrouping()
        let toggled = view.toggleTask(at: 1)
        undo.endUndoGrouping()
        check("clicking a task box checks it", toggled && view.string == "[x] Send the deck\nnext", view.string.debugDescription)
        undo.undo()
        check("undo unchecks it", view.string == "[ ] Send the deck\nnext", view.string.debugDescription)
        check("clicking task words does not toggle", !view.toggleTask(at: 8))

        // Undo and redo across typing.
        reset("Notes")
        type(" from Sam")
        check("typing lands", view.string == "Notes from Sam")
        undo.undo()
        check("undo removes the typing", view.string == "Notes", view.string.debugDescription)
        undo.redo()
        check("redo puts it back", view.string == "Notes from Sam", view.string.debugDescription)

        // Paste, through a private pasteboard so the real clipboard is left alone.
        reset("")
        let board = NSPasteboard(name: NSPasteboard.Name("com.derekhanson.silvanus.editor-check"))
        board.clearContents()
        let pasted = "## Pasted\n- **one**\n[ ] two"
        board.setString(pasted, forType: .string)
        undo.beginUndoGrouping()
        let read = view.readSelection(from: board, type: .string)
        undo.endUndoGrouping()
        check("paste inserts the Markdown exactly", read && view.string == pasted, view.string.debugDescription)
        check("pasted text is styled", font(at: 4)?.pointSize == style.headingSizes[1] && traits(at: 15).contains(.boldFontMask))
        undo.undo()
        check("undo removes the paste", view.string == "", view.string.debugDescription)
        board.releaseGlobally()

        // Selection across the page.
        reset(EditorSpike.fixture, caret: 0)
        view.selectAll(nil)
        check("select all covers the page", view.selectedRange().length == (EditorSpike.fixture as NSString).length)
        check("styles survive select all", font(at: 3)?.pointSize == style.headingSizes[0])

        // Find runs in the visible spike window (Snapshot.runEditorSpikeIfRequested):
        // NSTextFinder does not search before the app finishes launching.

        // Round trip, byte for byte, on the fixture and on 5,000 lines.
        reset(EditorSpike.fixture)
        check("the fixture round-trips byte for byte", Array(view.string.utf8) == Array(EditorSpike.fixture.utf8))
        let big = EditorSpike.bigFixture(lines: 5000)
        reset(big)
        check("5,000 lines round-trip byte for byte", view.string == big)
        type("**x**")
        undo.undo()
        check("an edit then undo round-trips", view.string == big)
        check("TextKit 2 is still active at the end", view.isTextKit2)

        window.orderOut(nil)
        print(failures == 0 ? "EDITOR CHECK PASS \(count) checks" : "EDITOR CHECK FAIL \(failures) of \(count) checks")
        return failures == 0 ? 0 : 1
    }
}
