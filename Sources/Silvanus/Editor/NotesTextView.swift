import AppKit
import SilvanusKit

/// The notes canvas's look, from design/KIT.md "Type" and "Notes canvas text". Fonts come
/// from `KitType` and colors from `Ink`; every size and color the editor uses is here.
struct EditorStyle {
    /// Body 16 / 24. H1 is `title` (24 bold), H2 `heading` (20 bold), H3 `subheading`
    /// (18 semibold); deeper headings use `subheading` too.
    let bodyRole = KitType.body
    let headingRoles: [KitType] = [.title, .heading, .subheading]
    /// List items sit 28 apart: a 24 pt line and 4 between items.
    let listItemSpacing: CGFloat = 4
    /// Space above a heading that isn't the first line, for H1, H2, and H3 (deeper headings
    /// take H3's), and below every heading. From KIT.md "Notes canvas text": a list's last
    /// line to the next H2 is 32 baseline to baseline, a paragraph (then an empty line) to an
    /// H3 58.5, and a heading to its first item 28 to 30. H1 has no measure and keeps 8.
    let headingSpaceBefore: [CGFloat] = [8, 5.5, 13.5]
    let headingSpaceAfter: CGFloat = 3
    /// KIT.md "Bullets": a top-level bullet's marker centers this far in from the text start,
    /// and its text (and wrapped lines) start `bulletTextIndent` in, so the first letter's
    /// ink lands at x 246 (the glyph's side bearing adds about a point).
    let bulletCenter: CGFloat = 8
    let bulletTextIndent: CGFloat = 24
    let tabInterval: CGFloat = 24

    /// Where the first line sits (KIT.md "Notes canvas text"): text starts at x 221 in the
    /// window, 12 after the canvas edge at 209, and the first line box starts 11 under the
    /// 46 pt header. With the glyphs centered in the 24 pt box, the baseline lands 18.5
    /// into it, at y 75.5, and a body line's cap top at y 64.
    let leadingInset = Metric.contentX - Metric.canvasX
    let topInset: CGFloat = 11

    let text = Ink.appKit(.text)
    /// Markers on the caret's line.
    let markerActive = Ink.appKit(.textSecondary)
    /// Markers on every other line: faded, never hidden.
    let markerFaded = Ink.appKit(.textSecondary, alpha: 0.5)
    let quote = Ink.appKit(.textSecondary)
    let done = Ink.appKit(.textSecondary)
    /// Task boxes are controls; gold is fill only, so they use accent text.
    let taskBox = Ink.appKit(.accentText)
    let codeBackground = Ink.appKit(.divider, alpha: 0.6)
    let caret = Ink.appKit(.text)

    let body = KitType.nsFont(.body)
    let headings: [NSFont]
    let code = KitType.nsCodeFont(in: .body)

    init() {
        headings = headingRoles.map(KitType.nsFont)
    }

    var bodySize: CGFloat { bodyRole.size }

    func headingRole(_ level: Int) -> KitType { headingRoles[min(level, headingRoles.count) - 1] }
    func headingFont(_ level: Int) -> NSFont { headings[min(level, headings.count) - 1] }

    /// A paragraph whose lines are `role`'s line height apart, with the glyphs centered in
    /// each line box, as KIT.md measures (cap top 64, baseline 75.5, wrapped lines 24 apart).
    /// TextKit puts a fixed line height's extra space above the glyphs, so each line is set
    /// half the extra shorter and the other half goes in as line spacing. (A baseline offset
    /// would center the glyphs too, but TextKit 2 takes it off the line's height: body lines
    /// came out 21.5 apart, not 24.)
    func paragraph(_ role: KitType, font: NSFont, headIndent: CGFloat = 0, firstLineHeadIndent: CGFloat = 0,
                   spaceBefore: CGFloat = 0, spaceAfter: CGFloat = 0) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        let lift = centering(font, role)
        p.minimumLineHeight = role.lineHeight - lift
        p.maximumLineHeight = role.lineHeight - lift
        p.lineSpacing = lift
        p.defaultTabInterval = tabInterval
        p.tabStops = []
        p.headIndent = headIndent
        p.firstLineHeadIndent = firstLineHeadIndent
        p.paragraphSpacingBefore = spaceBefore
        p.paragraphSpacing = spaceAfter
        return p
    }

    /// Half the space a role's line box adds to the font's own line: how far the glyphs move
    /// up to sit centered in the box.
    func centering(_ font: NSFont, _ role: KitType) -> CGFloat {
        let natural = ceil(font.ascender - font.descender + font.leading)
        return max(0, (role.lineHeight - natural) / 2)
    }

    var typing: [NSAttributedString.Key: Any] {
        [.font: body, .foregroundColor: text, .paragraphStyle: paragraph(bodyRole, font: body)]
    }

}

extension NSAttributedString.Key {
    /// Marks Markdown syntax the styler fades and brightens (value: `true`). Selection
    /// changes recolor only these ranges.
    static let markdownMarker = NSAttributedString.Key("SilvanusMarkdownMarker")
    /// Marks the text inside a code span (value: `true`): spell check skips it.
    static let markdownCode = NSAttributedString.Key("SilvanusMarkdownCode")
}

/// Styles the Markdown in place. It only sets attributes: the characters stay exactly
/// what was typed. Each edit restyles the paragraphs it touched, never the whole note;
/// moving the caret only recolors markers.
final class MarkdownStyler: NSObject {
    let style = EditorStyle()
    weak var textView: NSTextView?
    /// The paragraphs shown with bright markers: the selection's lines.
    private(set) var active = NSRange(location: NSNotFound, length: 0)
    /// Paragraphs edited and not yet restyled.
    private var pending: NSRange?
    /// Seconds spent in the last restyle, for the benchmark.
    private(set) var lastRestyle: Double = 0
    /// For the checks: full restyles run, paragraphs styled, and marker-only recolors.
    private(set) var restyles = 0
    private(set) var styledParagraphs = 0
    private(set) var markerRecolors = 0

    /// True while an input method holds marked text (kana before it is committed).
    /// Restyling then would replace the marked text's attributes under the input method.
    private var isComposing: Bool { textView?.hasMarkedText() ?? false }

    /// The paragraphs the selection touches.
    func selectionParagraphs() -> NSRange? {
        guard let textView, let storage = textView.textStorage else { return nil }
        let ns = storage.mutableString
        var union: NSRange?
        for value in textView.selectedRanges {
            let r = value.rangeValue
            guard r.location <= ns.length else { continue }
            let p = ns.paragraphRange(for: NSRange(location: r.location, length: min(r.length, ns.length - r.location)))
            union = union.map { NSUnionRange($0, p) } ?? p
        }
        return union
    }

    /// Brightens the selection's markers and fades the ones it left. Only marker colors
    /// change, so selecting the whole page costs one pass over the marker ranges.
    func selectionChanged() {
        guard pending == nil, !isComposing, let storage = textView?.textStorage,
              let now = selectionParagraphs(), now != active else { return }
        storage.beginEditing()
        if let old = clamped(active, storage.length) { recolorMarkers(in: old, storage, bright: false) }
        recolorMarkers(in: now, storage, bright: true)
        storage.endEditing()
        active = now
    }

    private func clamped(_ range: NSRange, _ length: Int) -> NSRange? {
        guard range.location != NSNotFound, range.location <= length else { return nil }
        return NSRange(location: range.location, length: min(NSMaxRange(range), length) - range.location)
    }

    private func recolorMarkers(in range: NSRange, _ storage: NSTextStorage, bright: Bool) {
        markerRecolors += 1
        let color = bright ? style.markerActive : style.markerFaded
        storage.enumerateAttribute(.markdownMarker, in: range) { value, sub, _ in
            if value != nil { storage.addAttribute(.foregroundColor, value: color, range: sub) }
        }
    }

    /// Styles each paragraph that intersects `range`. A paragraph is active (bright
    /// markers) when it intersects `activeAt`.
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
        styledParagraphs += 1
        let isActive = activeAt.map { NSIntersectionRange($0, full).length > 0 || $0.location == start } ?? false
        let line = Substring(ns.substring(with: NSRange(location: start, length: contentsEnd - start)))
        let block = MarkdownStyle.block(line)
        let runs = MarkdownStyle.lineRuns(line, offset: start)

        var base = style.typing
        // A top-level bullet: the space after its marker is widened so the text starts at
        // `bulletTextIndent` (where, and by how much).
        var bulletKern: (at: Int, kern: CGFloat)?
        if let level = block.kind.headingLevel {
            let role = style.headingRole(level), font = style.headingFont(level)
            base[.font] = font
            base[.paragraphStyle] = style.paragraph(role, font: font,
                                                    spaceBefore: start == 0 ? 0 : style.headingSpaceBefore[min(level, 3) - 1],
                                                    spaceAfter: style.headingSpaceAfter)
        } else if block.kind != .paragraph {
            // Wrapped lines hang under the text, after the marker.
            let prefix = line.utf16.prefix(block.marker.upperBound)
            let width = NSAttributedString(string: String(prefix) ?? "", attributes: [.font: style.body]).size().width
            var headIndent = ceil(width), firstLine: CGFloat = 0
            if block.kind == .bullet, block.indent.isEmpty, let bullet = bulletPlacement(line, block) {
                headIndent = style.bulletTextIndent
                firstLine = bullet.lead
                bulletKern = (start + block.marker.upperBound - 1, bullet.kern)
            }
            base[.paragraphStyle] = style.paragraph(style.bodyRole, font: style.body, headIndent: headIndent,
                                                    firstLineHeadIndent: firstLine,
                                                    spaceAfter: block.kind.isListItem ? style.listItemSpacing : 0)
        }
        storage.setAttributes(base, range: full)
        if let bulletKern {
            storage.addAttribute(.kern, value: bulletKern.kern, range: NSRange(location: bulletKern.at, length: 1))
        }

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
        var codeRanges: [NSRange] = []
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
                storage.addAttributes([.font: style.code, .backgroundColor: style.codeBackground,
                                       .markdownCode: true], range: r)
                codeRanges.append(r)
            default: break
            }
        }
        let marker = isActive ? style.markerActive : style.markerFaded
        for run in runs where run.role == .marker {
            storage.addAttributes([.foregroundColor: marker, .markdownMarker: true], range: nsRange(run.range))
        }
        if let box = block.box {
            // The task box is a control, so it stays visible on every line.
            let r = NSRange(location: start + box.lowerBound, length: box.count)
            storage.addAttribute(.foregroundColor, value: style.taskBox, range: r)
            storage.removeAttribute(.markdownMarker, range: r)
        }
        // A span that just became code drops the spelling marks it had as plain words.
        for r in codeRanges { (textView as? NotesTextView)?.clearSpelling(in: r) }
        return full
    }
}

extension MarkdownStyler {
    /// Where a top-level bullet's marker goes (KIT.md "Bullets"): `lead` moves the dash so it
    /// centers `bulletCenter` in, and `kern` widens the space after it so the text starts
    /// `bulletTextIndent` in. Nil when the marker isn't one character and a space.
    func bulletPlacement(_ line: Substring, _ block: MarkdownStyle.Block) -> (lead: CGFloat, kern: CGFloat)? {
        guard block.marker.count == 2 else { return nil }
        let marker = String(line.utf16.prefix(block.marker.upperBound).dropFirst(block.marker.lowerBound)) ?? ""
        let attributes: [NSAttributedString.Key: Any] = [.font: style.body]
        let dash = NSAttributedString(string: String(marker.prefix(1)), attributes: attributes).size().width
        let whole = NSAttributedString(string: marker, attributes: attributes).size().width
        let lead = max(0, style.bulletCenter - dash / 2)
        return (lead, max(0, style.bulletTextIndent - lead - whole))
    }
}

extension MarkdownStyler: @MainActor NSTextStorageDelegate {
    /// Characters changed: note the paragraphs the edit touched (and the one after a
    /// split line), and move the bright range with the text. They're restyled right
    /// after the edit, in `restylePending`: attribute changes made inside the edit widen
    /// its range, and NSTextView then puts the caret at the end of the paragraph.
    func textStorage(_ storage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        let ns = storage.mutableString
        let first = ns.paragraphRange(for: NSRange(location: min(editedRange.location, ns.length), length: 0))
        let last = ns.paragraphRange(for: NSRange(location: min(NSMaxRange(editedRange), ns.length), length: 0))
        let touched = NSUnionRange(first, last)
        pending = pending.map { NSUnionRange($0, touched) } ?? touched
        (textView as? NotesTextView)?.onCharactersChanged?()
        shiftActive(editedRange: editedRange, delta: delta, touched: touched)
        // Edits that never reach didChangeText (setting `string`) still get styled.
        DispatchQueue.main.async { [weak self] in self?.restylePending() }
    }

    /// Keeps `active` on the same text after an edit: past the edit it moves by `delta`;
    /// overlapping it, it grows to cover the touched paragraphs.
    private func shiftActive(editedRange: NSRange, delta: Int, touched: NSRange) {
        guard active.location != NSNotFound else { return }
        let oldEnd = NSMaxRange(editedRange) - delta
        if active.location >= oldEnd {
            active.location += delta
        } else if NSMaxRange(active) > editedRange.location || active.location == editedRange.location {
            let end = max(NSMaxRange(active) + delta, NSMaxRange(touched))
            let start = min(active.location, touched.location)
            active = NSRange(location: start, length: max(0, end - start))
        }
    }

    /// Styles the paragraphs the last edits touched, as one attribute-only pass, then
    /// sets the bright markers from the selection as it is now. Waits while an input
    /// method holds marked text; `NotesTextView.unmarkText` and the commit restyle then.
    func restylePending() {
        guard let range = pending, !isComposing, let storage = textView?.textStorage else { return }
        pending = nil
        restyles += 1
        let t0 = CFAbsoluteTimeGetCurrent()
        let length = storage.length
        let clampedRange = NSRange(location: min(range.location, length),
                                   length: max(0, min(NSMaxRange(range), length) - min(range.location, length)))
        let caret = selectionParagraphs()
        storage.beginEditing()
        styleParagraphs(in: clampedRange, storage, activeAt: caret)
        // Markers outside the restyled lines that were bright fade; the caret's brighten.
        if let old = clamped(active, length), old != caret { recolorMarkers(in: old, storage, bright: false) }
        if let caret { recolorMarkers(in: caret, storage, bright: true) }
        storage.endEditing()
        active = caret ?? NSRange(location: NSNotFound, length: 0)
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
    /// For the checks: whole-text loads, and changes from disk applied in place.
    private(set) var loads = 0
    private(set) var externalChanges = 0
    /// Called for every change to the characters: typing, paste, undo and redo alike.
    var onCharactersChanged: (() -> Void)?
    private var fallbackObserver: NSObjectProtocol?

    /// When each line was written during the recording, drawn as `mm:ss` in a margin on
    /// the trailing side, never in the text. Nil hides the margin and gives the text its
    /// full width back.
    var marginTimes: NoteTimes? {
        didSet {
            guard marginTimes != oldValue else { return }
            if (marginTimes == nil) != (oldValue == nil) { placeMargin() }
            marginView?.needsDisplay = true
        }
    }
    private var marginView: MarginTimesView?

    /// Text starts at the leading inset whatever the trailing side reserves.
    override var textContainerOrigin: NSPoint {
        NSPoint(x: styler.style.leadingInset, y: textContainerInset.height)
    }

    /// The text container's width comes from a symmetric inset, so the margin is reserved by
    /// widening the inset and pinning the origin (above) to the leading edge: the text keeps
    /// x 221 and wraps before the times.
    private func placeMargin() {
        let style = styler.style
        let trailing = marginTimes == nil ? style.leadingInset : Metric.noteTimeMargin
        textContainerInset = NSSize(width: (style.leadingInset + trailing) / 2, height: style.topInset)
        if marginTimes != nil, marginView == nil {
            let view = MarginTimesView(frame: bounds)
            view.autoresizingMask = [.width, .height]
            view.textView = self
            addSubview(view)
            marginView = view
        } else if marginTimes == nil {
            marginView?.removeFromSuperview()
            marginView = nil
        }
    }

    /// A scroll view holding a TextKit 2 notes view, set up for Markdown.
    static func scrollable() -> (NSScrollView, NotesTextView) {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        // The window's hidden title bar must not push the text down or under the header:
        // the editor's frame starts below the header, and its insets are its own.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
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
        let style = styler.style
        textContainer?.lineFragmentPadding = 0
        textContainerInset = NSSize(width: style.leadingInset, height: style.topInset)
        insertionPointColor = style.caret
        typingAttributes = style.typing
        fallbackObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.willSwitchToNSLayoutManagerNotification, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.fallbacks += 1
                print("EDITOR TextKit 2 fell back to TextKit 1")
            }
        }
    }

    /// The Summary page's reader: the same styling and find bar, but nothing can be typed,
    /// pasted, toggled, or dropped, and no spell check marks. It has no save path.
    func makeReadOnly() {
        isEditable = false
        isSelectable = true
        isContinuousSpellCheckingEnabled = false
        allowsUndo = false
        usesFindBar = true
        isIncrementalSearchingEnabled = true
    }

    var isTextKit2: Bool { textLayoutManager != nil && fallbacks == 0 }

    /// Replaces the whole text. The edit styles every paragraph once and clears undo.
    func load(_ markdown: String) {
        loads += 1
        string = markdown
        styler.restylePending()
        styler.selectionChanged()
        undoManager?.removeAllActions(withTarget: self)
    }

    /// Takes a new text from disk, changing only the part that differs, so the caret
    /// stays on the same words when the change was elsewhere. It's one undoable step,
    /// like a paste, so the undo stack still fits the text.
    func applyExternal(_ markdown: String) {
        guard let storage = textStorage else { return }
        // A reader has no caret to keep and no undo: it just shows the new text.
        if !isEditable { load(markdown); return }
        let change = TextChange.between(storage.string, markdown)
        guard !change.isEmpty else { return }
        let range = NSRange(location: change.range.lowerBound, length: change.range.count)
        guard shouldChangeText(in: range, replacementString: change.replacement) else { return }
        externalChanges += 1
        let caret = selectedRange()
        storage.replaceCharacters(in: range, with: change.replacement)
        let start = change.caret(caret.location)
        let end = change.caret(NSMaxRange(caret))
        setSelectedRange(NSRange(location: start, length: max(0, end - start)))
        didChangeText()
    }

    override func didChangeText() {
        styler.restylePending()
        styler.selectionChanged()
        super.didChangeText()
        marginView?.needsDisplay = true
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !stillSelecting { styler.selectionChanged() }
    }

    /// The input method ended its marked text: restyle once, now that it's plain text.
    override func unmarkText() {
        super.unmarkText()
        styler.restylePending()
        styler.selectionChanged()
    }

    // MARK: Spelling

    /// Spell check skips code spans: the checker's marks go only on the parts of `range`
    /// outside them, and the code parts are cleared.
    override func setSpellingState(_ value: Int, range charRange: NSRange) {
        for (part, isCode) in spellingParts(of: charRange) {
            super.setSpellingState(isCode ? 0 : value, range: part)
        }
    }

    /// `range` split into runs inside and outside code spans, in order.
    func spellingParts(of range: NSRange) -> [(NSRange, isCode: Bool)] {
        guard let storage = textStorage, range.location != NSNotFound else { return [] }
        let clampedRange = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard clampedRange.length > 0 else { return [(range, false)] }
        var parts: [(NSRange, isCode: Bool)] = []
        storage.enumerateAttribute(.markdownCode, in: clampedRange) { value, sub, _ in
            parts.append((sub, value != nil))
        }
        return parts
    }

    fileprivate func clearSpelling(in range: NSRange) {
        super.setSpellingState(0, range: range)
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
        guard sel.length == 0, block.kind != .paragraph, block.kind.headingLevel == nil,
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
        guard MarkdownStyle.blockKind(text).isListItem else { return super.insertTab(sender) }
        replace(NSRange(location: start, length: 0), with: "\t", keeping: sel)
    }

    override func insertBacktab(_ sender: Any?) {
        let sel = selectedRange()
        let (start, text) = line(at: sel.location)
        guard MarkdownStyle.blockKind(text).isListItem else { return super.insertBacktab(sender) }
        let lead = text.utf16.prefix(4)
        let count = lead.first == 9 ? 1 : lead.prefix { $0 == 32 }.count
        guard count > 0 else { return }
        replace(NSRange(location: start, length: count), with: "", keeping: sel)
    }

    // MARK: Task boxes

    /// ⌘⌫ deletes to the start of the line while typing, as it does in every Mac text view,
    /// and never reaches Meeting > Move to Trash, which shares the shortcut.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if window?.firstResponder === self, flags == .command,
           event.charactersIgnoringModifiers == "\u{7F}" {
            deleteToBeginningOfLine(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        if isEditable, event.clickCount == 1, event.modifierFlags.intersection([.shift, .command, .option]).isEmpty,
           toggleTask(at: index) {
            return
        }
        super.mouseDown(with: event)
    }

    /// Toggles "[ ]" and "[x]" when `index` is on a task box: from just before "[" up to,
    /// not including, the insertion point after "]". Undoable.
    @discardableResult
    func toggleTask(at index: Int) -> Bool {
        let (start, text) = line(at: index)
        let block = MarkdownStyle.block(text)
        guard case .task(let done) = block.kind, let box = block.box,
              index >= start + box.lowerBound, index < start + box.upperBound else { return false }
        let mark = NSRange(location: start + box.lowerBound + 1, length: 1)
        replace(mark, with: done ? " " : "x", keeping: selectedRange())
        return true
    }
}

extension Metric {
    /// The notes' trailing margin while they have timestamps: room for "1:00:00" in
    /// `monoSmall` and a gap before it.
    static let noteTimeMargin: CGFloat = 64
}

/// Draws each timed line's `mm:ss` in the notes' trailing margin, level with the line's
/// first row, in `monoSmall` and `textSecondary`. It sits over the text view, takes no
/// clicks, and reads the times and line positions from it.
final class MarginTimesView: NSView {
    weak var textView: NotesTextView?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let textView, let times = textView.marginTimes, !times.isEmpty,
              let layout = textView.textLayoutManager else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: KitType.nsFont(.monoSmall),
            .foregroundColor: Ink.appKit(.textSecondary),
        ]
        let origin = textView.textContainerOrigin
        let right = bounds.maxX - textView.styler.style.leadingInset
        let start = layout.textViewportLayoutController.viewportRange?.location ?? layout.documentRange.location
        layout.enumerateTextLayoutFragments(from: start, options: []) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
            if frame.minY > dirtyRect.maxY { return false }
            guard frame.maxY >= dirtyRect.minY, let paragraph = fragment.textElement as? NSTextParagraph else { return true }
            var line = paragraph.attributedString.string
            if line.hasSuffix("\n") { line.removeLast() }
            guard let time = times.time(for: line) else { return true }
            let text = Clock.text(time) as NSString
            let size = text.size(withAttributes: attributes)
            // Level with the first row: centered in its line box.
            let row = fragment.textLineFragments.first?.typographicBounds ?? CGRect(origin: .zero, size: frame.size)
            let y = frame.minY + row.minY + (row.height - size.height) / 2
            text.draw(at: NSPoint(x: right - size.width, y: y), withAttributes: attributes)
            return true
        }
    }
}
