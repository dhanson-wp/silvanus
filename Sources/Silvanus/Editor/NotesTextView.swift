import AppKit
import SilvanusKit

/// The notes editor's look. Placeholders until the design kit lands; every
/// size and color the editor uses comes from here.
struct EditorStyle {
    var bodySize: CGFloat = 15
    /// H1, H2, H3. Deeper headings use the body size, semibold.
    var headingSizes: [CGFloat] = [24, 19, 16]
    var lineHeightMultiple: CGFloat = 1.4
    var headingSpaceBefore: CGFloat = 8
    var tabInterval: CGFloat = 24
    var inset = NSSize(width: 32, height: 24)

    var text: NSColor { .labelColor }
    /// Markers on the caret's line.
    var markerActive: NSColor { .secondaryLabelColor }
    /// Markers on every other line: faded, never hidden.
    var markerFaded: NSColor { .tertiaryLabelColor }
    var quote: NSColor { .secondaryLabelColor }
    var done: NSColor { .secondaryLabelColor }
    var taskBox: NSColor { .controlAccentColor }
    var codeBackground: NSColor { .quaternarySystemFill }

    let body: NSFont
    let headings: [NSFont]
    let code: NSFont

    init() {
        body = .systemFont(ofSize: bodySize)
        headings = headingSizes.map { .systemFont(ofSize: $0, weight: .semibold) }
        code = .monospacedSystemFont(ofSize: bodySize * 0.92, weight: .regular)
    }

    func headingFont(_ level: Int) -> NSFont {
        level <= headings.count ? headings[level - 1] : .systemFont(ofSize: bodySize, weight: .semibold)
    }

    func paragraph(headIndent: CGFloat = 0, spaceBefore: CGFloat = 0) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = lineHeightMultiple
        p.defaultTabInterval = tabInterval
        p.tabStops = []
        p.headIndent = headIndent
        p.paragraphSpacingBefore = spaceBefore
        return p
    }

    var typing: [NSAttributedString.Key: Any] {
        [.font: body, .foregroundColor: text, .paragraphStyle: paragraph()]
    }
}

/// Styles the Markdown in place. It only sets attributes: the characters stay
/// exactly what was typed. Each edit restyles the paragraphs it touched, never
/// the whole note.
final class MarkdownStyler: NSObject {
    let style = EditorStyle()
    weak var textView: NSTextView?
    /// The paragraphs shown with bright markers (the caret's lines).
    private var active = NSRange(location: NSNotFound, length: 0)
    /// Paragraphs edited and not yet restyled, and the caret's paragraph after the edit.
    private var pending: NSRange?
    private var pendingCaret: NSRange?
    /// Seconds spent in the last restyle, for the benchmark.
    private(set) var lastRestyle: Double = 0

    /// Restyles the old and new caret paragraphs so markers fade and return.
    func selectionChanged() {
        guard pending == nil, let textView, let storage = textView.textStorage else { return }
        let ns = storage.mutableString
        var union: NSRange?
        for value in textView.selectedRanges {
            let r = value.rangeValue
            guard r.location <= ns.length else { continue }
            let p = ns.paragraphRange(for: NSRange(location: r.location, length: min(r.length, ns.length - r.location)))
            union = union.map { NSUnionRange($0, p) } ?? p
        }
        guard let now = union, now != active else { return }
        storage.beginEditing()
        if active.location != NSNotFound, active.location <= ns.length {
            let old = NSRange(location: active.location, length: min(active.length, ns.length - active.location))
            styleParagraphs(in: old, storage, activeAt: nil)
        }
        styleParagraphs(in: now, storage, activeAt: now)
        storage.endEditing()
        active = now
    }

    /// Styles each paragraph that intersects `range`. A paragraph is active
    /// (bright markers) when it intersects `activeAt`.
    private func styleParagraphs(in range: NSRange, _ storage: NSTextStorage, activeAt: NSRange?) {
        let ns = storage.mutableString
        var location = range.location
        repeat {
            let p = styleParagraph(at: location, storage, activeAt: activeAt)
            location = NSMaxRange(p)
        } while location < NSMaxRange(range) && location < ns.length
    }

    @discardableResult
    private func styleParagraph(at location: Int, _ storage: NSTextStorage, activeAt: NSRange?) -> NSRange {
        let ns = storage.mutableString
        var start = 0, end = 0, contentsEnd = 0
        ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd,
                             for: NSRange(location: min(location, ns.length), length: 0))
        let full = NSRange(location: start, length: end - start)
        guard full.length > 0 else { return full }
        let isActive = activeAt.map { NSIntersectionRange($0, full).length > 0 || $0.location == start } ?? false
        let line = Substring(ns.substring(with: NSRange(location: start, length: contentsEnd - start)))
        let block = MarkdownStyle.block(line)
        let runs = MarkdownStyle.lineRuns(line, offset: start)

        var base = style.typing
        switch block.kind {
        case .heading(let level):
            base[.font] = style.headingFont(level)
            base[.paragraphStyle] = style.paragraph(spaceBefore: start == 0 ? 0 : style.headingSpaceBefore)
        case .bullet, .numbered, .task, .quote:
            // Wrapped lines hang under the text, after the marker.
            let prefix = (line as Substring).utf16.prefix(block.marker.upperBound)
            let width = NSAttributedString(string: String(prefix) ?? "", attributes: [.font: style.body]).size().width
            base[.paragraphStyle] = style.paragraph(headIndent: ceil(width))
        case .paragraph:
            break
        }
        storage.setAttributes(base, range: full)

        func nsRange(_ r: Range<Int>) -> NSRange { NSRange(location: r.lowerBound, length: r.count) }
        for run in runs {
            switch run.role {
            case .quote: storage.addAttribute(.foregroundColor, value: style.quote, range: nsRange(run.range))
            case .done:
                storage.addAttributes([.foregroundColor: style.done,
                                       .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: nsRange(run.range))
            default: break
            }
        }
        for run in runs {
            let r = nsRange(run.range)
            switch run.role {
            case .bold, .italic:
                let trait: NSFontTraitMask = run.role == .bold ? .boldFontMask : .italicFontMask
                storage.enumerateAttribute(.font, in: r) { value, sub, _ in
                    let font = (value as? NSFont) ?? style.body
                    storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: sub)
                }
            case .code:
                storage.addAttributes([.font: style.code, .backgroundColor: style.codeBackground], range: r)
            default: break
            }
        }
        let marker = isActive ? style.markerActive : style.markerFaded
        for run in runs where run.role == .marker {
            storage.addAttribute(.foregroundColor, value: marker, range: nsRange(run.range))
        }
        if let box = block.box {
            // The task box is a control, so it stays visible on every line.
            storage.addAttribute(.foregroundColor, value: style.taskBox,
                                 range: NSRange(location: start + box.lowerBound, length: box.count))
        }
        return full
    }
}

extension MarkdownStyler: @MainActor NSTextStorageDelegate {
    /// Characters changed: note the paragraphs the edit touched (and the one
    /// after a split line). They're restyled right after the edit, in
    /// `restylePending`: attribute changes made inside the edit widen its
    /// range, and NSTextView then puts the caret at the end of the paragraph.
    func textStorage(_ storage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        let ns = storage.mutableString
        let first = ns.paragraphRange(for: NSRange(location: min(editedRange.location, ns.length), length: 0))
        let last = ns.paragraphRange(for: NSRange(location: min(NSMaxRange(editedRange), ns.length), length: 0))
        let touched = NSUnionRange(first, last)
        pending = pending.map { NSUnionRange($0, touched) } ?? touched
        pendingCaret = last
        // Edits that never reach didChangeText (setting `string`) still get styled.
        DispatchQueue.main.async { [weak self] in self?.restylePending() }
    }

    /// Styles the paragraphs the last edits touched, as one attribute-only pass.
    func restylePending() {
        guard let range = pending, let storage = textView?.textStorage else { return }
        pending = nil
        let t0 = CFAbsoluteTimeGetCurrent()
        let length = storage.length
        let clamped = NSRange(location: min(range.location, length),
                              length: max(0, min(NSMaxRange(range), length) - min(range.location, length)))
        storage.beginEditing()
        styleParagraphs(in: clamped, storage, activeAt: pendingCaret)
        storage.endEditing()
        active = pendingCaret ?? active
        lastRestyle = CFAbsoluteTimeGetCurrent() - t0
    }
}

/// The notes canvas: one NSTextView on TextKit 2, holding plain Markdown.
/// Return continues lists and tasks, Return on an empty item ends the list,
/// Tab and Shift-Tab indent list items, and clicking a task box toggles it.
final class NotesTextView: NSTextView {
    let styler = MarkdownStyler()
    /// Times TextKit 2 fell back to TextKit 1 (logged; should stay 0).
    private(set) var fallbacks = 0
    private var fallbackObserver: NSObjectProtocol?

    /// A scroll view holding a TextKit 2 notes view, set up for Markdown.
    static func scrollable() -> (NSScrollView, NotesTextView) {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let view = NotesTextView(usingTextLayoutManager: true)
        view.configure()
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = view
        return (scroll, view)
    }

    private func configure() {
        styler.textView = self
        textStorage?.delegate = styler
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        drawsBackground = false
        // Substitutions would change the Markdown under the writer's hands.
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = true
        textContainerInset = styler.style.inset
        typingAttributes = styler.style.typing
        fallbackObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.willSwitchToNSLayoutManagerNotification, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fallbacks += 1
                print("EDITOR TextKit 2 fell back to TextKit 1")
            }
        }
    }

    var isTextKit2: Bool { textLayoutManager != nil && fallbacks == 0 }

    /// Replaces the whole text. The edit styles every paragraph once.
    func load(_ markdown: String) {
        string = markdown
        styler.restylePending()
        styler.selectionChanged()
        undoManager?.removeAllActions(withTarget: self)
    }

    override func didChangeText() {
        styler.restylePending()
        styler.selectionChanged()
        super.didChangeText()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting { styler.selectionChanged() }
    }

    // MARK: Lines

    private var ns: NSString { textStorage?.mutableString ?? "" }

    /// The line around `location`: where it starts, and its text without the newline.
    private func line(at location: Int) -> (start: Int, text: Substring) {
        var start = 0, end = 0, contentsEnd = 0
        ns.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd,
                             for: NSRange(location: min(location, ns.length), length: 0))
        return (start, Substring(ns.substring(with: NSRange(location: start, length: contentsEnd - start))))
    }

    /// Replaces characters as one undoable edit, keeping the caret where it was
    /// relative to the text after the change.
    private func replace(_ range: NSRange, with string: String, keeping selection: NSRange) {
        guard shouldChangeText(in: range, replacementString: string) else { return }
        textStorage?.replaceCharacters(in: range, with: string)
        didChangeText()
        let delta = (string as NSString).length - range.length
        var sel = selection
        if sel.location >= NSMaxRange(range) {
            sel.location += delta
        } else if sel.location > range.location {
            sel.location = max(range.location, sel.location + delta)
        }
        setSelectedRange(NSRange(location: min(sel.location, ns.length), length: 0))
    }

    // MARK: Return, Tab, Shift-Tab

    override func insertNewline(_ sender: Any?) {
        let sel = selectedRange()
        let (start, text) = line(at: sel.location)
        let block = MarkdownStyle.block(text)
        guard sel.length == 0, block.kind != .paragraph, !isHeading(block.kind),
              sel.location >= start + block.marker.upperBound else {
            super.insertNewline(sender)
            return
        }
        let u = Array(text.utf16)
        if block.content.isEmpty || u[block.content].allSatisfy({ $0 == 32 }) {
            // Return on an empty item ends the list.
            let whole = NSRange(location: start, length: u.count)
            replace(whole, with: "", keeping: NSRange(location: start, length: 0))
            return
        }
        let indent = String(utf16CodeUnits: Array(u[block.indent]), count: block.indent.count)
        let marker = String(utf16CodeUnits: Array(u[block.marker]), count: block.marker.count)
        insertText("\n" + indent + Self.nextMarker(after: marker, kind: block.kind), replacementRange: sel)
    }

    private func isHeading(_ kind: MarkdownStyle.BlockKind) -> Bool {
        if case .heading = kind { return true }
        return false
    }

    /// The marker that continues a list: the same bullet, the next number,
    /// an open task box, or another quote.
    static func nextMarker(after marker: String, kind: MarkdownStyle.BlockKind) -> String {
        switch kind {
        case .numbered:
            let digits = marker.prefix { $0.isNumber }
            let rest = marker.dropFirst(digits.count)
            return "\((Int(digits) ?? 0) + 1)\(rest.isEmpty ? ". " : rest)"
        case .task:
            // Keep a "- " in front when the list uses one.
            let lead = marker.hasPrefix("[") ? "" : String(marker.prefix(2))
            return lead + "[ ] "
        case .quote:
            return "> "
        default:
            return marker.hasSuffix(" ") ? marker : marker + " "
        }
    }

    override func insertTab(_ sender: Any?) {
        let sel = selectedRange()
        let (start, text) = line(at: sel.location)
        guard isListItem(MarkdownStyle.blockKind(text)) else { return super.insertTab(sender) }
        replace(NSRange(location: start, length: 0), with: "\t", keeping: sel)
    }

    override func insertBacktab(_ sender: Any?) {
        let sel = selectedRange()
        let (start, text) = line(at: sel.location)
        guard isListItem(MarkdownStyle.blockKind(text)) else { return super.insertBacktab(sender) }
        let lead = text.utf16.prefix(4)
        let count = lead.first == 9 ? 1 : lead.prefix { $0 == 32 }.count
        guard count > 0 else { return }
        replace(NSRange(location: start, length: count), with: "", keeping: sel)
    }

    private func isListItem(_ kind: MarkdownStyle.BlockKind) -> Bool {
        switch kind {
        case .bullet, .numbered, .task: true
        default: false
        }
    }

    // MARK: Task boxes

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        if event.clickCount == 1, event.modifierFlags.intersection([.shift, .command, .option]).isEmpty,
           toggleTask(at: index) {
            return
        }
        super.mouseDown(with: event)
    }

    /// Toggles "[ ]" and "[x]" when `index` is on a task box. Undoable.
    @discardableResult
    func toggleTask(at index: Int) -> Bool {
        let (start, text) = line(at: index)
        let block = MarkdownStyle.block(text)
        guard case .task(let done) = block.kind, let box = block.box,
              index >= start + box.lowerBound, index <= start + box.upperBound else { return false }
        let mark = NSRange(location: start + box.lowerBound + 1, length: 1)
        replace(mark, with: done ? " " : "x", keeping: selectedRange())
        return true
    }
}
