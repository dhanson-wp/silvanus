import AppKit
import SwiftUI
import SilvanusKit
import ExceptionHandling

// The editor's dev aids. The window uses the same MarkdownEditor as the notes canvas.
//   APP_EDITOR_SPIKE=1 Silvanus   open the editor alone in a window with a fictional note
//   APP_EDITOR_SPIKE=1 APP_SNAPSHOT=<dir> APP_STORE=/tmp/... Silvanus
//                                 snapshot it light and dark, caret on a heading and on a plain line
//   APP_EDITOR_CHECK=1 Silvanus   run the editor's checks headless, print PASS/FAIL, exit 0 or 1
//   APP_EDITOR_BENCH=1 Silvanus   time 200 keystrokes through MarkdownEditor in a 5,000-line note, print median and p95, exit

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

    /// A fictional meeting with every construct the editor styles.
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

    /// Runs the checks or the benchmark when asked; returns the exit code. Output is
    /// line-buffered only for these runs, so their progress shows as it happens.
    static func runHeadlessIfRequested() -> Int32? {
        guard let run = HeadlessRun(env: env) else { return nil }
        setvbuf(stdout, nil, _IOLBF, 0)
        NSExceptionHandler.default().setExceptionHandlingMask(Int(NSLogUncaughtExceptionMask | NSLogTopLevelExceptionMask | NSLogOtherExceptionMask))
        switch run {
        case .check: var checks = EditorChecks(); return checks.run()
        case .bench: return bench()
        }
    }

    /// Which headless run the environment asks for, if any.
    enum HeadlessRun {
        case check, bench
        init?(env: [String: String]) {
            if env["APP_EDITOR_CHECK"] == "1" { self = .check } else if env["APP_EDITOR_BENCH"] == "1" { self = .bench } else { return nil }
        }
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

    /// A MarkdownEditor with a plain binding, in a titled window shaped like the main one
    /// (hidden title bar, content under it) and placed off screen. Counts binding writes.
    @MainActor final class Hosted {
        final class Box {
            var text: String
            var sets = 0
            init(_ text: String) { self.text = text }
        }

        let box: Box
        let link = EditorLink()
        let window: NSWindow
        let hosting: NSHostingView<AnyView>
        private(set) var view: NotesTextView?
        private var revision = 0

        init(_ text: String, size: CGSize = CGSize(width: 760, height: 720)) {
            box = Box(text)
            window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -8000, y: -8000), size: size),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            hosting = NSHostingView(rootView: AnyView(EmptyView()))
            window.contentView = hosting
            update()
            window.orderFrontRegardless()
            spin(0.05)
            if let view { window.makeFirstResponder(view) }
        }

        /// Re-renders, so SwiftUI calls updateNSView with the binding's value.
        func update() {
            revision += 1
            let box = box
            let binding = Binding<String>(get: { box.text }, set: { box.text = $0; box.sets += 1 })
            hosting.rootView = AnyView(MarkdownEditor(text: binding, link: link) { [weak self] in self?.view = $0 }
                .id("editor").overlay(Text("\(revision)").opacity(0)))
            hosting.layoutSubtreeIfNeeded()
        }

        func spin(_ seconds: TimeInterval) {
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        }
    }

    // MARK: Benchmark

    private static func bench() -> Int32 {
        let lines = 5000
        let text = bigFixture(lines: lines)
        let loadStart = CFAbsoluteTimeGetCurrent()
        let host = Hosted(text)
        guard let view = host.view else { print("BENCH no editor"); return 1 }
        view.textLayoutManager?.textViewportLayoutController.layoutViewport()
        let loadMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
        print("BENCH through MarkdownEditor with a binding, in a titled window off screen")
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
        var insert: [Double] = [], restyle: [Double] = [], layout: [Double] = [], draw: [Double] = [], loop: [Double] = []
        let setsBefore = host.box.sets
        for i in 0..<200 {
            let c = String(typed[i % typed.count])
            let t0 = CFAbsoluteTimeGetCurrent()
            view.insertText(c, replacementRange: view.selectedRange())
            let t1 = CFAbsoluteTimeGetCurrent()
            view.textLayoutManager?.textViewportLayoutController.layoutViewport()
            let t2 = CFAbsoluteTimeGetCurrent()
            view.displayIfNeeded()
            let t3 = CFAbsoluteTimeGetCurrent()
            // One pass of the run loop: queued restyles, SwiftUI updates, undo grouping.
            RunLoop.main.run(until: Date())
            let t4 = CFAbsoluteTimeGetCurrent()
            insert.append((t1 - t0) * 1000)
            restyle.append(view.styler.lastRestyle * 1000)
            layout.append((t2 - t1) * 1000)
            draw.append((t3 - t2) * 1000)
            loop.append((t4 - t3) * 1000)
        }
        let total = (0..<200).map { insert[$0] + layout[$0] + draw[$0] + loop[$0] }
        let setsWhileTyping = host.box.sets - setsBefore
        print("BENCH 200 inserts at line 2,500 of \(lines) (ms):")
        for (name, values) in [("insertText incl. restyle", insert), ("  restyle alone", restyle),
                               ("viewport layout", layout), ("draw", draw), ("run loop pass", loop),
                               ("total per keystroke", total)] {
            print("BENCH   \(name.padding(toLength: 26, withPad: " ", startingAt: 0)) median \(fmt(median(values)))  p95 \(fmt(p95(values)))  max \(fmt(values.max() ?? 0))")
        }
        print("BENCH binding writes while typing without a pause: \(setsWhileTyping)")
        // The pause: the text goes to the binding once, then SwiftUI hands it back.
        let p0 = CFAbsoluteTimeGetCurrent()
        host.link.flush()
        let p1 = CFAbsoluteTimeGetCurrent()
        let loads = view.loads
        host.update()
        let p2 = CFAbsoluteTimeGetCurrent()
        print("BENCH one push to the binding after a pause: \(fmt((p1 - p0) * 1000)) ms")
        print("BENCH SwiftUI update with the echo: \(fmt((p2 - p1) * 1000)) ms, loads \(view.loads - loads)")
        print("BENCH TextKit 2 after typing: \(view.isTextKit2)")
        let ok = median(total) < 8 && setsWhileTyping == 0 && view.loads == loads
        print(ok ? "BENCH PASS median \(fmt(median(total))) ms under 8" : "BENCH FAIL")
        host.window.orderOut(nil)
        return ok ? 0 : 1
    }

    static func median(_ v: [Double]) -> Double { let s = v.sorted(); return s[s.count / 2] }
    static func p95(_ v: [Double]) -> Double { let s = v.sorted(); return s[Int(Double(s.count - 1) * 0.95)] }
    static func fmt(_ v: Double) -> String { String(format: "%.3f", v) }
}

/// Exercises the editor against a real NotesTextView (and, for the binding and saving,
/// a real MarkdownEditor) and prints PASS or FAIL for each.
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
        textView()
        binding()
        placement()
        saving()
        boundedSaves()
        switching()
        conflictCopyFails()
        trashing()
        closingKeepsUnsaved()
        lineEndings()
        try? FileManager.default.removeItem(at: CheckStore.root)
        print(failures == 0 ? "EDITOR CHECK PASS \(count) checks" : "EDITOR CHECK FAIL \(failures) of \(count) checks")
        return failures == 0 ? 0 : 1
    }

    // MARK: The text view

    private mutating func textView() {
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
        /// The line pitch: the line, plus the spacing that centers its glyphs (EditorStyle.paragraph).
        func lineHeight(at i: Int) -> CGFloat? {
            (attr(.paragraphStyle, at: i) as? NSParagraphStyle).map { $0.maximumLineHeight + $0.lineSpacing }
        }
        func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        /// Runs `body` as one undo group, as an event would.
        func grouped(_ body: () -> Void) {
            undo.beginUndoGrouping()
            body()
            undo.endUndoGrouping()
        }
        let newline = #selector(NSResponder.insertNewline(_:))

        check("TextKit 2 is active after setup", view.isTextKit2)

        // KIT.md type: body 16 / 24, H1 24 bold, H2 20 bold, H3 18 semibold.
        reset("# Acme kickoff\n## Agenda\n### Decisions\nPlain words\n- Item")
        let weight = { (i: Int) in NSFontManager.shared.weight(of: font(at: i) ?? style.body) }
        check("body is 16 on a 24 pt line", font(at: 40)?.pointSize == 16 && lineHeight(at: 40) == 24,
              "\(String(describing: font(at: 40))) \(String(describing: lineHeight(at: 40)))")
        check("H1 is 24 bold on 28", font(at: 3)?.pointSize == 24 && traits(at: 3).contains(.boldFontMask) && lineHeight(at: 3) == 28)
        check("H2 is 20 bold on 24", font(at: 18)?.pointSize == 20 && traits(at: 18).contains(.boldFontMask) && lineHeight(at: 18) == 24)
        check("H3 is 18 semibold on 22", font(at: 30)?.pointSize == 18 && weight(30) >= 7 && weight(30) < weight(3)
              && lineHeight(at: 30) == 22, "weight \(weight(30)) vs bold \(weight(3))")
        check("list items sit 4 apart", (attr(.paragraphStyle, at: 52) as? NSParagraphStyle)?.paragraphSpacing == 4)
        check("text is Ink.text", color(at: 40) == style.text)
        // Laid out, not just styled: wrapped body lines and list items land 24 and 28 apart
        // (TextKit 2 once took a baseline offset off every body line: 21.5 apart).
        reset(String(repeating: "Wrapped words go on and on. ", count: 40) + "\n- One\n- Two")
        if let tlm = view.textLayoutManager {
            tlm.ensureLayout(for: tlm.documentRange)
            var tops: [CGFloat] = []
            tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: []) { fragment in
                tops += fragment.textLineFragments.map { fragment.layoutFragmentFrame.minY + $0.typographicBounds.minY }
                return true
            }
            let wrapped = tops.count > 3 ? tops[1] - tops[0] : 0
            let items = tops.count > 3 ? tops[tops.count - 1] - tops[tops.count - 2] : 0
            check("wrapped body lines are 24 apart and list items 28", wrapped == 24 && items == 28, "\(wrapped) \(items)")
        }

        // Format as you type.
        reset("")
        type("# Acme kickoff")
        check("# formats a heading as you type", font(at: 3)?.pointSize == style.headingFont(1).pointSize, "\(String(describing: font(at: 3)))")
        reset("")
        type("## Agenda")
        check("## gives the H2 size", font(at: 4)?.pointSize == style.headingFont(2).pointSize)
        reset("Agenda", caret: 0)
        type("### ")
        check("a marker typed before existing words formats the line", font(at: 5)?.pointSize == style.headingFont(3).pointSize,
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

        // (b) Review Focus 4: an input method's marked text survives restyling.
        reset("# Title", caret: 7)
        spin()
        let restylesBefore = view.styler.restyles
        grouped { view.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0)) }
        spin()
        grouped { view.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0)) }
        spin()
        check("marked text stays marked while the line would restyle",
              view.hasMarkedText() && view.markedRange() == NSRange(location: 7, length: 2),
              "marked \(view.hasMarkedText()) \(view.markedRange())")
        check("no restyle runs while text is marked", view.styler.restyles == restylesBefore,
              "\(view.styler.restyles - restylesBefore) restyles")
        view.styler.selectionChanged()
        view.styler.restylePending()
        check("caret moves inside marked text don't restyle either", view.styler.restyles == restylesBefore
              && view.hasMarkedText())
        grouped { view.unmarkText() }
        spin()
        check("unmarking restyles once", view.styler.restyles == restylesBefore + 1,
              "\(view.styler.restyles - restylesBefore) restyles")
        check("the kana join the heading", view.string == "# Titleかな" && font(at: 8)?.pointSize == style.headingFont(1).pointSize,
              "\(view.string.debugDescription) \(String(describing: font(at: 8)))")
        reset("- Item ", caret: 7)
        spin()
        let beforeCommit = view.styler.restyles
        grouped { view.setMarkedText("かめ", selectedRange: NSRange(location: 2, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0)) }
        spin()
        grouped { view.insertText("亀", replacementRange: view.markedRange()) }
        spin()
        check("committing kana restyles once and keeps the text", view.styler.restyles == beforeCommit + 1
              && view.string == "- Item 亀" && !view.hasMarkedText(),
              "\(view.styler.restyles - beforeCommit) restyles, \(view.string.debugDescription)")

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

        // Task boxes, and (e) the box's hit range ends before the "]" insertion point.
        reset("[ ] Send the deck\nnext")
        undo.beginUndoGrouping()
        let toggled = view.toggleTask(at: 1)
        undo.endUndoGrouping()
        check("clicking a task box checks it", toggled && view.string == "[x] Send the deck\nnext", view.string.debugDescription)
        undo.undo()
        check("undo unchecks it", view.string == "[ ] Send the deck\nnext", view.string.debugDescription)
        check("clicking task words does not toggle", !view.toggleTask(at: 8))
        check("a click just after ] does not toggle", !view.toggleTask(at: 3) && view.string == "[ ] Send the deck\nnext")
        var onOpen = false, onClose = false
        grouped { onOpen = view.toggleTask(at: 0) }
        grouped { onClose = view.toggleTask(at: 2) }
        check("a click on [ or ] toggles", onOpen && onClose && view.string == "[ ] Send the deck\nnext")
        reset("- [ ] Draft")
        var dash = false
        grouped { dash = view.toggleTask(at: 4) }
        check("a dash task's box ends before its ] insertion point too", !view.toggleTask(at: 5) && dash)

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
        check("pasted text is styled", font(at: 4)?.pointSize == style.headingFont(2).pointSize && traits(at: 15).contains(.boldFontMask))
        // (d) The bright markers follow the selection, not where the paste ended.
        let caretLine = (pasted as NSString).paragraphRange(for: view.selectedRange())
        check("after a paste the caret's line is the active one", view.styler.active == caretLine,
              "\(view.styler.active) vs \(caretLine)")
        undo.undo()
        check("undo removes the paste", view.string == "", view.string.debugDescription)
        board.releaseGlobally()

        // (d) An edit above the caret (a change from disk) keeps the active line on the caret.
        reset("# One\n# Two\n# Three", caret: 18)
        spin()
        grouped { view.applyExternal("# Zero\n# One\n# Two\n# Three") }
        spin()
        let threeLine = (view.string as NSString).paragraphRange(for: view.selectedRange())
        check("a change above the caret keeps it on the same words", view.selectedRange().location == 25,
              "\(view.selectedRange())")
        check("the active range is the caret's line after the restyle", view.styler.active == threeLine,
              "\(view.styler.active) vs \(threeLine)")
        check("only the caret's line has bright markers", color(at: 20) == style.markerActive
              && color(at: 0) == style.markerFaded && color(at: 7) == style.markerFaded && color(at: 13) == style.markerFaded,
              "\([0, 7, 13, 20].map { color(at: $0) == style.markerActive })")
        undo.undo()
        check("a change from disk undoes as one step", view.string == "# One\n# Two\n# Three", view.string.debugDescription)
        undo.redo()
        check("and redoes", view.string == "# Zero\n# One\n# Two\n# Three", view.string.debugDescription)

        // (g) Spell check skips code spans.
        reset("Plain `codez` wrod")
        spin()
        let parts = view.spellingParts(of: NSRange(location: 0, length: 18))
        let code = parts.filter(\.isCode).map(\.0)
        check("spell check skips the code span", code == [NSRange(location: 7, length: 5)], "\(parts)")
        check("spell check covers the words around it", parts.filter { !$0.isCode }.map(\.0)
              == [NSRange(location: 0, length: 7), NSRange(location: 12, length: 6)], "\(parts)")
        grouped { view.setSpellingState(NSAttributedString.SpellingState.spelling.rawValue, range: NSRange(location: 0, length: 18)) }
        check("marking spelling over a code span keeps its characters", view.string == "Plain `codez` wrod")

        // (c) Selection across the page recolors markers only.
        reset(EditorSpike.fixture, caret: 0)
        spin()
        let styledBefore = view.styler.styledParagraphs, recolorsBefore = view.styler.markerRecolors
        view.selectAll(nil)
        check("select all covers the page", view.selectedRange().length == (EditorSpike.fixture as NSString).length)
        check("styles survive select all", font(at: 3)?.pointSize == style.headingFont(1).pointSize)
        check("select all restyles no paragraph", view.styler.styledParagraphs == styledBefore,
              "\(view.styler.styledParagraphs - styledBefore) paragraphs")
        let lastMarker = (EditorSpike.fixture as NSString).range(of: "- [x]").location
        check("select all brightens every marker", view.styler.markerRecolors > recolorsBefore && color(at: lastMarker) == style.markerActive)

        // Round trip, byte for byte, on the fixture and on 5,000 lines.
        reset(EditorSpike.fixture)
        check("the fixture round-trips byte for byte", Array(view.string.utf8) == Array(EditorSpike.fixture.utf8))
        let big = EditorSpike.bigFixture(lines: 5000)
        reset(big, caret: 0)
        spin()
        let bigStyled = view.styler.styledParagraphs
        let t0 = CFAbsoluteTimeGetCurrent()
        grouped { view.selectAll(nil) }
        let selectAllMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        check("select all on 5,000 lines restyles nothing", view.styler.styledParagraphs == bigStyled)
        print("INFO select all on 5,000 lines: \(EditorSpike.fmt(selectAllMs)) ms (marker colors only)")
        reset(big)
        check("5,000 lines round-trip byte for byte", view.string == big)
        type("**x**")
        undo.undo()
        check("an edit then undo round-trips", view.string == big)
        check("TextKit 2 is still active at the end", view.isTextKit2)

        // (f) Only the headless runs change how stdout buffers.
        check("an ordinary launch is not a headless run", EditorSpike.HeadlessRun(env: [:]) == nil
              && EditorSpike.HeadlessRun(env: ["APP_EDITOR_CHECK": "1"]) != nil)

        window.orderOut(nil)
    }

    // MARK: (a) The binding

    private mutating func binding() {
        let host = EditorSpike.Hosted("# Acme kickoff\n")
        guard let view = host.view else { check("the hosted editor appears", false); return }
        let loads = view.loads
        let end = (view.string as NSString).length
        view.setSelectedRange(NSRange(location: end, length: 0))
        for c in "Sam shares the plan" { view.insertText(String(c), replacementRange: view.selectedRange()) }
        check("typing writes nothing to the binding keystroke by keystroke", host.box.sets == 0, "\(host.box.sets) writes")
        host.spin(0.5)
        check("after a pause the binding gets the text once", host.box.sets == 1 && host.box.text == view.string,
              "\(host.box.sets) writes, \(host.box.text.debugDescription)")
        host.update()
        host.spin(0.05)
        check("the binding's echo never loads the editor", view.loads == loads && view.externalChanges == 0,
              "loads \(view.loads - loads), external \(view.externalChanges)")
        let t0 = CFAbsoluteTimeGetCurrent()
        host.update()
        print("INFO SwiftUI update with the echo: \(EditorSpike.fmt((CFAbsoluteTimeGetCurrent() - t0) * 1000)) ms")
        view.setSelectedRange(NSRange(location: 2, length: 0))
        host.box.text = "# Acme kickoff\nSam shares the plan\n- Budget\n"
        host.update()
        check("a new value from the binding replaces the text in place", view.string == host.box.text
              && view.externalChanges == 1 && view.selectedRange().location == 2,
              "\(view.string.debugDescription) caret \(view.selectedRange())")
        view.insertText("x", replacementRange: NSRange(location: (view.string as NSString).length, length: 0))
        host.link.flush()
        check("a flush hands typing over at once", host.box.sets == 2 && host.box.text.hasSuffix("x"))
        host.window.orderOut(nil)
    }

    // MARK: (g) Where the text sits

    private mutating func placement() {
        let root = CheckStore.root.appending(path: "placement")
        let library = MeetingLibrary(root: root, trash: { try FileManager.default.removeItem(at: $0) })
        let meeting = Meeting(info: MeetingInfo(id: "check-placement", title: "Acme kickoff", series: "Acme kickoff",
                                                start: Date(), end: Date(), attendees: ["Sam Rivera"]),
                              notes: "Agenda for the Acme kickoff\n- Scope\n")
        _ = try? library.save(meeting)
        let document = NotesDocument(meetingID: meeting.id, library: library)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -8000, y: -8000), size: Metric.windowDefault),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PaneLayout(sidebarVisible: true) {
            EmptyView()
        } sidebar: {
            Color.clear
        } header: {
            Color.clear
        } canvas: {
            NotesEditor(document: document)
        })
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let view = document.link.textView, let metrics = view.firstLineMetrics() else {
            check("the canvas editor lays out", false)
            return
        }
        check("text starts at x 221", abs(metrics.x - Metric.contentX) < 0.5, "x \(metrics.x)")
        check("the first line's cap top is at y 64", abs(metrics.capTop - 64) < 0.5, "cap top \(metrics.capTop)")
        check("the first line clears the header", metrics.lineTop >= Metric.headerHeight, "line top \(metrics.lineTop)")
        print("INFO first line: x \(EditorSpike.fmt(metrics.x)), line top \(EditorSpike.fmt(metrics.lineTop)), cap top \(EditorSpike.fmt(metrics.capTop)), baseline \(EditorSpike.fmt(metrics.baseline))")
        document.link.textView?.load("# Acme kickoff\nAgenda")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        if let heading = view.firstLineMetrics() {
            check("a first-line heading is not clipped under the header", heading.lineTop >= Metric.headerHeight,
                  "line top \(heading.lineTop)")
        }
        document.close()
        window.orderOut(nil)
    }

    // MARK: Saving and changes on disk

    private mutating func saving() {
        let root = CheckStore.root.appending(path: "saving")
        let library = MeetingLibrary(root: root, trash: { try FileManager.default.removeItem(at: $0) })
        let meeting = Meeting(info: MeetingInfo(id: "check-saving", title: "Weekly sync", series: "Weekly sync",
                                                start: Date(), end: Date(), attendees: ["Sam Rivera", "Jordan Lee"]),
                              notes: "# Weekly sync\n- On track\n")
        guard let folder = try? library.save(meeting) else { check("the check store is writable", false); return }
        let file = folder.appending(path: MeetingFolder.notes)
        func disk() -> String { (try? String(contentsOf: file, encoding: .utf8)) ?? "" }
        func spin(_ s: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

        let document = NotesDocument(meetingID: meeting.id, library: library)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -8000, y: -8000), size: CGSize(width: 700, height: 500)),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: NotesEditor(document: document))
        window.orderFrontRegardless()
        spin(0.1)
        guard let view = document.link.textView else { check("the notes editor appears", false); return }
        check("the canvas opens the meeting's notes.md", view.string == meeting.notes)

        let end = (view.string as NSString).length
        view.setSelectedRange(NSRange(location: end, length: 0))
        for c in "- Budget" { view.insertText(String(c), replacementRange: view.selectedRange()) }
        spin(0.5)
        check("the note is not written while typing pauses under a second", disk() == meeting.notes && document.isDirty)
        spin(1.0)
        check("the note is written 1 s after typing stops", disk() == "# Weekly sync\n- On track\n- Budget" && !document.isDirty,
              disk().debugDescription)
        let savesAfterTyping = document.saves
        spin(0.3)
        check("our own save is not loaded back", document.reloads == 0 && view.externalChanges == 0)

        // Another app adds a line above the caret, replacing the file (an atomic save).
        view.setSelectedRange(NSRange(location: 16, length: 0)) // in "- On track"
        let outside = "# Weekly sync\nFrom the phone\n- On track\n- Budget"
        try? Data(outside.utf8).write(to: file, options: .atomic)
        spin(0.5)
        check("a change from another app shows in the editor", view.string == outside && document.reloads == 1,
              view.string.debugDescription)
        check("the caret stays on the same words", view.selectedRange().location == 31, "\(view.selectedRange())")
        check("loading it writes nothing back", document.saves == savesAfterTyping)

        // Written in place (appended), not replaced.
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data("\n- Hiring".utf8))
            try? handle.close()
        }
        spin(0.5)
        check("a change written in place shows too", view.string == outside + "\n- Hiring", view.string.debugDescription)

        // Closing the window saves at once, with typing the binding hadn't seen yet.
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.insertText("!", replacementRange: view.selectedRange())
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        check("closing the window saves at once", disk() == outside + "\n- Hiring!", disk().debugDescription)

        // Quitting saves at once.
        view.insertText("~", replacementRange: view.selectedRange())
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApp)
        check("quitting saves at once", disk() == outside + "\n- Hiring!~", disk().debugDescription)

        // Unsaved typing and another app's change on other lines merge, then save.
        view.insertText("?", replacementRange: view.selectedRange())
        spin(0.4)
        let theirs = "Phone note\n" + disk()
        try? Data(theirs.utf8).write(to: file, options: .atomic)
        spin(0.4)
        let merged = "Phone note\n" + outside + "\n- Hiring!~?"
        check("typing and another app's change on other lines merge", view.string == merged, view.string.debugDescription)
        check("the merge is saved", disk() == merged, disk().debugDescription)
        let undo = view.undoManager
        undo?.undo()
        check("the merge undoes as one step", view.string == outside + "\n- Hiring!~?", view.string.debugDescription)
        undo?.redo()
        spin(1.6)

        // Both changed the same line: the typing stays, the other version is kept beside it.
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.insertText("#", replacementRange: view.selectedRange())
        spin(0.4)
        try? Data("Overwritten elsewhere".utf8).write(to: file, options: .atomic)
        spin(0.4)
        check("on a conflict the typing stays", view.string == merged + "#", view.string.debugDescription)
        let copy = document.conflicts.first.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        check("on a conflict the other version is kept as notes.conflict-*.md", copy == "Overwritten elsewhere"
              && document.conflicts.first?.lastPathComponent.hasPrefix("notes.conflict-") == true,
              "\(document.conflicts)")
        check("and the typing is saved over notes.md", disk() == merged + "#", disk().debugDescription)

        // A missing notes.md is not an empty note; an emptied one is, in place and undoable.
        try? FileManager.default.removeItem(at: file)
        spin(0.4)
        check("a missing notes.md leaves the editor alone", view.string == merged + "#", view.string.debugDescription)
        let loads = view.loads
        try? Data().write(to: file)
        spin(0.4)
        check("an emptied notes.md empties the editor in place", view.string.isEmpty && view.loads == loads)
        undo?.undo()
        check("and that undoes", view.string == merged + "#", view.string.debugDescription)
        spin(1.6)
        check("the undo saves", disk() == merged + "#", disk().debugDescription)

        // A save that fails shows the reason with Retry, and Retry saves.
        try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        view.insertText("!", replacementRange: NSRange(location: (view.string as NSString).length, length: 0))
        document.saveNow()
        check("a failed save shows its reason", document.saveError != nil && document.isDirty, "\(document.saveError ?? "none")")
        print("INFO save error banner: Couldn't save notes: \(document.saveError ?? "")")
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        document.saveNow()
        check("Retry saves and clears it", document.saveError == nil && disk() == merged + "#!", disk().debugDescription)

        document.close()
        window.orderOut(nil)
    }

    // MARK: Saving while typing never pauses

    private mutating func boundedSaves() {
        let root = CheckStore.root.appending(path: "bounded")
        let library = MeetingLibrary(root: root, trash: { try FileManager.default.removeItem(at: $0) })
        let meeting = Meeting(info: MeetingInfo(id: "check-bounded", title: "Design review", series: "Design review",
                                                start: Date(), end: Date(), attendees: ["Priya Natarajan"]), notes: "")
        _ = try? library.save(meeting)
        let document = NotesDocument(meetingID: meeting.id, library: library)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -8000, y: -8000), size: CGSize(width: 700, height: 500)),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: NotesEditor(document: document))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        guard let view = document.link.textView else { check("the notes editor appears", false); return }
        let words = Array("Typing that never stops for long. ")
        for i in 0..<50 {
            view.insertText(String(words[i % words.count]), replacementRange: view.selectedRange())
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        check("typing every 0.2 s for 10 s saves at least 3 times", document.saves >= 3, "\(document.saves) saves")
        document.close()
        window.orderOut(nil)
    }

    // MARK: Switching meetings mid-typing

    private mutating func switching() {
        let root = CheckStore.root.appending(path: "switching")
        let library = MeetingLibrary(root: root, trash: { try FileManager.default.removeItem(at: $0) })
        let a = Meeting(info: MeetingInfo(id: "check-a", title: "Acme kickoff", series: "Acme kickoff",
                                          start: Date(), end: Date(), attendees: ["Sam Rivera"]), notes: "Agenda\n")
        let b = Meeting(info: MeetingInfo(id: "check-b", title: "Weekly sync", series: "Weekly sync",
                                          start: Date().addingTimeInterval(-86_400), end: Date(), attendees: ["Jordan Lee"]),
                        notes: "Status\n")
        guard let folderA = try? library.save(a), let folderB = try? library.save(b) else { check("the check store is writable", false); return }
        let model = AppModel(library: library)
        model.reload()
        model.selection = a.id
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -8000, y: -8000), size: CGSize(width: 700, height: 500)),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CheckCanvas().environment(model))
        window.orderFrontRegardless()
        var found: NotesTextView?
        for _ in 0..<40 where found == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            found = window.contentView.flatMap(NotesTextView.find)
        }
        guard let view = found else { check("the canvas shows an editor", false); return }
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        for c in "- Budget" { view.insertText(String(c), replacementRange: view.selectedRange()) }
        model.selection = b.id
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        func read(_ folder: URL) -> String { (try? String(contentsOf: folder.appending(path: MeetingFolder.notes), encoding: .utf8)) ?? "" }
        check("switching meetings mid-typing saves the typing to the old meeting", read(folderA) == "Agenda\n- Budget",
              read(folderA).debugDescription)
        check("and leaves the new meeting's notes alone", read(folderB) == "Status\n", read(folderB).debugDescription)
        check("the app's copy of the old meeting has the saved notes",
              model.meetings.first { $0.id == a.id }?.notes == "Agenda\n- Budget")
        // Before the app finishes launching SwiftUI leaves the old editor's view in the
        // window; the snapshot run checks that a running app keeps only one.
        func editors(_ v: NSView) -> [NotesTextView] { ((v as? NotesTextView).map { [$0] } ?? []) + v.subviews.flatMap(editors) }
        let shown = window.contentView.map(editors)?.map(\.string) ?? []
        check("the canvas now shows the new meeting", shown.contains("Status\n"), "\(shown)")
        window.orderOut(nil)
    }

    // MARK: A conflict copy that can't be written

    private mutating func conflictCopyFails() {
        let root = CheckStore.root.appending(path: "conflict-fails")
        let library = MeetingLibrary(root: root, trash: { try FileManager.default.removeItem(at: $0) })
        let meeting = Meeting(info: MeetingInfo(id: "check-conflict", title: "Acme kickoff", series: "Acme kickoff",
                                                start: Date(), end: Date(), attendees: ["Sam Rivera"]), notes: "# Acme\n")
        guard let folder = try? library.save(meeting) else { check("the check store is writable", false); return }
        let file = folder.appending(path: MeetingFolder.notes)
        func disk() -> String { (try? String(contentsOf: file, encoding: .utf8)) ?? "" }
        func copies() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasPrefix("notes.conflict-") }
        }
        func spin(_ s: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
        let document = NotesDocument(meetingID: meeting.id, library: library)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -8000, y: -8000), size: CGSize(width: 700, height: 500)),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: NotesEditor(document: document))
        window.orderFrontRegardless()
        spin(0.1)
        guard let view = document.link.textView else { check("the notes editor appears", false); return }
        document.writeConflictCopy = { _ in throw CocoaError(.fileWriteNoPermission) }
        view.insertText("!", replacementRange: NSRange(location: 6, length: 0))
        spin(0.4)
        try? Data("Rewritten elsewhere\n".utf8).write(to: file, options: .atomic)
        spin(0.4)
        check("when the conflict copy fails, notes.md keeps the other version", disk() == "Rewritten elsewhere\n" && copies().isEmpty,
              disk().debugDescription)
        check("and the banner shows why, with the typing kept", document.saveError != nil && document.isDirty
              && view.string == "# Acme!\n", "\(document.saveError ?? "none") \(view.string.debugDescription)")
        view.insertText("?", replacementRange: NSRange(location: 7, length: 0))
        spin(3.6)
        check("no timer writes over it while the copy can't be made", disk() == "Rewritten elsewhere\n", disk().debugDescription)
        document.writeConflictCopy = { try library.saveConflictCopy($0, for: meeting.id) }
        document.saveNow()
        let copy = copies().first.flatMap { try? String(contentsOf: folder.appending(path: $0), encoding: .utf8) }
        check("Retry writes the copy first, then the notes", copy == "Rewritten elsewhere\n" && copies().count == 1
              && disk() == "# Acme!?\n" && document.saveError == nil, "\(copies()) \(disk().debugDescription)")
        document.close()
        window.orderOut(nil)
    }

    // MARK: Trashing the open meeting, or its folder vanishing

    private mutating func trashing() {
        let root = CheckStore.root.appending(path: "trashing")
        let trashFolder = CheckStore.root.appending(path: "Trash")
        try? FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        // A stand-in Trash under the check store, so the trashed folder can be read.
        let library = MeetingLibrary(root: root, trash: {
            try FileManager.default.moveItem(at: $0, to: trashFolder.appending(path: $0.lastPathComponent))
        })
        let a = Meeting(info: MeetingInfo(id: "check-trash", title: "Design review", series: "Design review",
                                          start: Date(), end: Date(), attendees: ["Priya Natarajan"]), notes: "Agenda\n")
        let b = Meeting(info: MeetingInfo(id: "check-vanish", title: "Weekly sync", series: "Weekly sync",
                                          start: Date().addingTimeInterval(-86_400), end: Date(), attendees: ["Jordan Lee"]),
                        notes: "Status\n")
        guard let folderA = try? library.save(a), let folderB = try? library.save(b) else { check("the check store is writable", false); return }
        let model = AppModel(library: library)
        model.reload()
        model.selection = a.id
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -8000, y: -8000), size: CGSize(width: 700, height: 500)),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CheckCanvas().environment(model))
        window.orderFrontRegardless()
        func editor(showing text: String) -> NotesTextView? {
            func all(_ v: NSView) -> [NotesTextView] { ((v as? NotesTextView).map { [$0] } ?? []) + v.subviews.flatMap(all) }
            for _ in 0..<40 {
                if let found = window.contentView.map(all)?.first(where: { $0.string == text }) { return found }
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            return nil
        }
        guard let view = editor(showing: "Agenda\n") else { check("the canvas shows an editor", false); return }
        view.setSelectedRange(NSRange(location: 7, length: 0))
        for c in "- Budget" { view.insertText(String(c), replacementRange: view.selectedRange()) }
        try? model.moveToTrash(a.id)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let trashed = (try? String(contentsOf: trashFolder.appending(path: folderA.lastPathComponent).appending(path: MeetingFolder.notes),
                                   encoding: .utf8)) ?? ""
        func recoveredTexts() -> [String] {
            let dir = root.appending(path: "recovered")
            return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
                .compactMap { try? String(contentsOf: dir.appending(path: $0), encoding: .utf8) }
        }
        check("trashing the open meeting mid-typing keeps the typing", trashed == "Agenda\n- Budget"
              || recoveredTexts().contains("Agenda\n- Budget"), "trashed \(trashed.debugDescription), recovered \(recoveredTexts())")

        // The folder vanishes under the editor (deleted by another app): the typing goes to recovered/.
        model.selection = b.id
        guard let other = editor(showing: "Status\n") else { check("the canvas shows the other meeting", false); return }
        other.setSelectedRange(NSRange(location: 7, length: 0))
        for c in "- Hiring" { other.insertText(String(c), replacementRange: other.selectedRange()) }
        try? FileManager.default.removeItem(at: folderB)
        RunLoop.main.run(until: Date().addingTimeInterval(1.6))
        check("typing whose folder vanished is kept in recovered/", recoveredTexts().contains("Status\n- Hiring"),
              "\(recoveredTexts())")
        for c in " now" { other.insertText(String(c), replacementRange: other.selectedRange()) }
        RunLoop.main.run(until: Date().addingTimeInterval(1.6))
        let vanished = recoveredTexts().filter { $0.hasPrefix("Status") }
        check("later saves overwrite the same recovered file", vanished == ["Status\n- Hiring now"], "\(recoveredTexts())")
        check("and keep the app's copy current", model.meetings.first { $0.id == b.id }?.notes == "Status\n- Hiring now")
        window.orderOut(nil)
    }

    // MARK: Closing with text that couldn't be saved

    private mutating func closingKeepsUnsaved() {
        let root = CheckStore.root.appending(path: "closing")
        let library = MeetingLibrary(root: root, trash: { try FileManager.default.removeItem(at: $0) })
        let a = Meeting(info: MeetingInfo(id: "check-close", title: "Acme kickoff", series: "Acme kickoff",
                                          start: Date(), end: Date(), attendees: ["Sam Rivera"]), notes: "# Acme\n")
        let b = Meeting(info: MeetingInfo(id: "check-close-other", title: "Weekly sync", series: "Weekly sync",
                                          start: Date().addingTimeInterval(-86_400), end: Date(), attendees: ["Jordan Lee"]),
                        notes: "Status\n")
        guard let folderA = try? library.save(a), (try? library.save(b)) != nil else { check("the check store is writable", false); return }
        NotesDocument.conflictCopyOverride = { _ in throw CocoaError(.fileWriteNoPermission) }
        defer { NotesDocument.conflictCopyOverride = nil }
        let model = AppModel(library: library)
        model.reload()
        model.selection = a.id
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -8000, y: -8000), size: CGSize(width: 700, height: 500)),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CheckCanvas().environment(model))
        window.orderFrontRegardless()
        func all(_ v: NSView) -> [NotesTextView] { ((v as? NotesTextView).map { [$0] } ?? []) + v.subviews.flatMap(all) }
        var view: NotesTextView?
        for _ in 0..<40 where view == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            view = window.contentView.map(all)?.first { $0.string == "# Acme\n" }
        }
        guard let view else { check("the canvas shows an editor", false); return }
        view.insertText("!", replacementRange: NSRange(location: 6, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let file = folderA.appending(path: MeetingFolder.notes)
        try? Data("Rewritten elsewhere\n".utf8).write(to: file, options: .atomic)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        model.selection = b.id
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let dir = root.appending(path: "recovered")
        let kept = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .compactMap { try? String(contentsOf: dir.appending(path: $0), encoding: .utf8) }
        check("closing with a conflict copy that fails keeps our text in recovered/", kept == ["# Acme!\n"], "\(kept)")
        check("and leaves the other version in notes.md", (try? String(contentsOf: file, encoding: .utf8)) == "Rewritten elsewhere\n")
        window.orderOut(nil)
    }

    // MARK: Line endings

    private mutating func lineEndings() {
        let root = CheckStore.root.appending(path: "line-endings")
        let library = MeetingLibrary(root: root, trash: { try FileManager.default.removeItem(at: $0) })
        let meeting = Meeting(info: MeetingInfo(id: "check-crlf", title: "Weekly sync", series: "Weekly sync",
                                                start: Date(), end: Date(), attendees: ["Jordan Lee"]),
                              notes: "# Sync\r\n- On track\r\n")
        guard let folder = try? library.save(meeting) else { check("the check store is writable", false); return }
        let file = folder.appending(path: MeetingFolder.notes)
        let document = NotesDocument(meetingID: meeting.id, library: library)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -8000, y: -8000), size: CGSize(width: 700, height: 500)),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: NotesEditor(document: document))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        guard let view = document.link.textView else { check("the notes editor appears", false); return }
        check("a CRLF note opens with LF lines in the editor", view.string == "# Sync\n- On track\n" && document.lineEnding == .crlf,
              view.string.debugDescription)
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        for c in "- Typed" { view.insertText(String(c), replacementRange: view.selectedRange()) }
        view.insertText("\n", replacementRange: view.selectedRange())
        document.saveNow()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let disk = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        check("typed lines save with the file's CRLF endings", disk == "# Sync\r\n- On track\r\n- Typed\r\n", disk.debugDescription)
        check("and our own CRLF save isn't loaded back", document.reloads == 0)
        document.close()
        window.orderOut(nil)
    }
}

/// Where the checks write meetings: under APP_STORE when it's a scratch folder, else
/// a fresh folder in /tmp. Never the real meetings folder.
enum CheckStore {
    static let root: URL = {
        let base = Store.isScratch ? Store.root : URL(fileURLWithPath: "/tmp/Silvanus-editor-check-\(getpid())")
        return base.appending(path: "editor-check")
    }()
}

extension NotesTextView {
    /// The first notes editor in a view tree.
    static func find(in view: NSView) -> NotesTextView? {
        if let editor = view as? NotesTextView { return editor }
        for sub in view.subviews { if let found = find(in: sub) { return found } }
        return nil
    }

    /// Where the first line sits in the window, top-left origin: the text's left edge, the
    /// line box's top, the baseline, and the first character's cap top.
    func firstLineMetrics() -> (x: CGFloat, lineTop: CGFloat, baseline: CGFloat, capTop: CGFloat)? {
        guard let tlm = textLayoutManager, let window, let content = window.contentView,
              let storage = textStorage, storage.length > 0 else { return nil }
        tlm.ensureLayout(for: NSTextRange(location: tlm.documentRange.location))
        guard let fragment = tlm.textLayoutFragment(for: tlm.documentRange.location),
              let line = fragment.textLineFragments.first else { return nil }
        let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? styler.style.body
        let shift = storage.attribute(.baselineOffset, at: 0, effectiveRange: nil) as? CGFloat ?? 0
        let frame = fragment.layoutFragmentFrame
        let origin = textContainerOrigin
        let lineTop = origin.y + frame.minY + line.typographicBounds.minY
        let baseline = lineTop + line.glyphOrigin.y - shift
        let x = origin.x + frame.minX + line.typographicBounds.minX
        func toWindow(_ p: CGPoint) -> CGPoint {
            let w = convert(p, to: nil)
            return CGPoint(x: w.x, y: content.bounds.height - w.y)
        }
        let top = toWindow(CGPoint(x: x, y: lineTop))
        let base = toWindow(CGPoint(x: x, y: baseline))
        return (top.x, top.y, base.y, base.y - font.capHeight)
    }
}

/// The checks' canvas: the window's My notes page (MeetingPage, with the meeting header over
/// the notes) for the selected meeting, with its own open notes as ContentView keeps them.
private struct CheckCanvas: View {
    @Environment(AppModel.self) private var model
    @State private var documents = OpenNotes()

    var body: some View {
        MeetingPage(meeting: model.selectedMeeting, documents: documents)
    }
}
