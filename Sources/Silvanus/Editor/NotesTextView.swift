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
    /// Below a plain paragraph that has words, so lines written one after another read as
    /// paragraphs. An empty line adds none: it's already a 24 pt gap.
    let paragraphSpacing: CGFloat = 8
    /// Space above a heading that isn't the first line, for H1, H2, and H3 (deeper headings
    /// take H3's), and below each. A heading right after an empty line takes none above:
    /// the empty line is the gap. KIT.md "Notes canvas text".
    let headingSpaceBefore: [CGFloat] = [24, 20, 16]
    let headingSpaceAfter: [CGFloat] = [8, 8, 4]
    /// The dot drawn for a bullet's dash (KIT.md "Bullets"), and the bar drawn for a
    /// quote's ">".
    let bulletDiameter: CGFloat = 6
    let quoteBarWidth: CGFloat = 2
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
    /// Markers on the caret's line, and list numbers on every line.
    let markerActive = Ink.appKit(.textSecondary)
    /// Markers on every other line are hidden: clear, in a font too small to take room,
    /// so the line reads as rendered text. The characters stay in the note.
    let markerHidden = NSColor.clear
    let hiddenFont = NSFont.systemFont(ofSize: 0.01)
    let bullet = Ink.appKit(.text)
    let quoteBar = Ink.appKit(.textSecondary, alpha: 0.5)
    let quote = Ink.appKit(.textSecondary)
    let done = Ink.appKit(.textSecondary)
    /// Task boxes are controls: an open box is outlined in accent text (gold is fill only),
    /// a done one filled like a primary control, with its check in `onPrimary`.
    let taskBox = Ink.appKit(.accentText)
    let taskDone = Ink.appKit(.primaryControl)
    let taskCheck = Ink.appKit(.onPrimary)
    let taskBoxSize: CGFloat = 14
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
    /// Marks Markdown syntax the styler hides and shows (value: the NSFont it shows in).
    /// Selection changes touch only these ranges.
    static let markdownMarker = NSAttributedString.Key("SilvanusMarkdownMarker")
    /// A bullet's dash, drawn as a dot by `MarkdownLayoutFragment` (value: `true`).
    static let markdownBullet = NSAttributedString.Key("SilvanusMarkdownBullet")
    /// A quote's ">", drawn as a bar down the quote by `MarkdownLayoutFragment` (value: `true`).
    static let markdownQuoteBar = NSAttributedString.Key("SilvanusMarkdownQuoteBar")
    /// A task's "[ ]" or "[x]", drawn as a checkbox by `MarkdownLayoutFragment` (value: done, a Bool).
    static let markdownTask = NSAttributedString.Key("SilvanusMarkdownTask")
    /// Marks the text inside a code span (value: `true`): spell check skips it.
    static let markdownCode = NSAttributedString.Key("SilvanusMarkdownCode")
}

/// Styles the Markdown in place. It only sets attributes: the characters stay exactly
/// what was typed. Markers show only on the caret's line; elsewhere they're hidden, a
/// bullet's dash is drawn as a dot, and a quote's ">" as a bar. Each edit restyles the
/// paragraphs it touched (and the next one), never the whole note; moving the caret only
/// shows and hides markers.
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

    /// The lines whose markers show: each caret's line, and a selection's line when it stays
    /// on one. A selection across lines shows none, so the page doesn't reflow under it.
    func selectionParagraphs() -> NSRange? {
        guard let textView, let storage = textView.textStorage else { return nil }
        let ns = storage.mutableString
        var union: NSRange?
        for value in textView.selectedRanges {
            let r = value.rangeValue
            guard r.location <= ns.length else { continue }
            let p = ns.paragraphRange(for: NSRange(location: r.location, length: 0))
            guard NSMaxRange(r) <= NSMaxRange(p) || r.location == ns.length else { continue }
            union = union.map { NSUnionRange($0, p) } ?? p
        }
        return union
    }

    /// Shows the selection's markers and hides the ones it left. Only marker ranges
    /// change, so selecting the whole page costs one pass over them.
    func selectionChanged() {
        guard pending == nil, !isComposing, let storage = textView?.textStorage else { return }
        let now = selectionParagraphs() ?? NSRange(location: NSNotFound, length: 0)
        guard now != active else { return }
        storage.beginEditing()
        if let old = clamped(active, storage.length) { recolorMarkers(in: old, storage, bright: false) }
        if let shown = clamped(now, storage.length) { recolorMarkers(in: shown, storage, bright: true) }
        storage.endEditing()
        active = now
    }

    private func clamped(_ range: NSRange, _ length: Int) -> NSRange? {
        guard range.location != NSNotFound, range.location <= length else { return nil }
        return NSRange(location: range.location, length: min(NSMaxRange(range), length) - range.location)
    }

    private func recolorMarkers(in range: NSRange, _ storage: NSTextStorage, bright: Bool) {
        markerRecolors += 1
        storage.enumerateAttribute(.markdownMarker, in: range) { value, sub, _ in
            guard let shown = value as? NSFont else { return }
            storage.addAttributes(bright ? [.foregroundColor: style.markerActive, .font: shown]
                                         : [.foregroundColor: style.markerHidden, .font: style.hiddenFont], range: sub)
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
            // After an empty line (or at the top) the gap is already there.
            let afterEmpty = start == 0 || (start == 1 ? ns.character(at: 0) == 10
                                            : ns.character(at: start - 1) == 10 && ns.character(at: start - 2) == 10)
            let tier = min(level, 3) - 1
            base[.paragraphStyle] = style.paragraph(role, font: font,
                                                    spaceBefore: afterEmpty ? 0 : style.headingSpaceBefore[tier],
                                                    spaceAfter: style.headingSpaceAfter[tier])
        } else if block.kind == .paragraph {
            if !line.isEmpty {
                base[.paragraphStyle] = style.paragraph(style.bodyRole, font: style.body, spaceAfter: style.paragraphSpacing)
            }
        } else if block.kind != .paragraph {
            // Wrapped lines hang under the text, after the marker.
            let prefix = line.utf16.prefix(block.marker.upperBound)
            let width = NSAttributedString(string: String(prefix) ?? "", attributes: [.font: style.body]).size().width
            var headIndent = ceil(width), firstLine: CGFloat = 0
            if block.kind == .bullet, block.indent.isEmpty, let bullet = bulletPlacement(line, block) {
                headIndent = style.bulletTextIndent
                firstLine = bullet.lead
                bulletKern = (start + block.marker.upperBound - 1, bullet.kern)
            } else if block.kind == .bullet, let nested = nestedBulletPlacement(line, block) {
                headIndent = nested.textStart
                bulletKern = (start + block.marker.upperBound - 1, nested.kern)
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
        let blockMarker = nsRange((start + block.marker.lowerBound)..<(start + block.marker.upperBound))
        for run in runs where run.role == .marker {
            let r = nsRange(run.range)
            if r == blockMarker {
                switch block.kind {
                case .bullet:
                    // Always drawn as a dot; the dash keeps its room, unseen.
                    storage.addAttributes([.foregroundColor: style.markerHidden, .markdownBullet: true],
                                          range: NSRange(location: r.location, length: 1))
                    continue
                case .quote:
                    storage.addAttributes([.foregroundColor: style.markerHidden, .markdownQuoteBar: true],
                                          range: NSRange(location: r.location, length: 1))
                    continue
                case .numbered:
                    // The number is the rendered list: it shows on every line.
                    storage.addAttribute(.foregroundColor, value: style.markerActive, range: r)
                    continue
                case .task(let done):
                    // The box is always drawn as a checkbox and keeps its room, as does the space
                    // after it; a "- " in front hides like any marker.
                    if let box = block.box {
                        storage.addAttributes([.foregroundColor: style.markerHidden, .markdownTask: done],
                                              range: NSRange(location: start + box.lowerBound, length: box.count))
                        let lead = NSRange(location: r.location, length: start + box.lowerBound - r.location)
                        if lead.length > 0 { hideMarker(lead) }
                    }
                    continue
                default: break
                }
            }
            hideMarker(r)
        }
        /// Shows the marker on the caret's line, hides it elsewhere. Each part remembers the
        /// font it shows in.
        func hideMarker(_ r: NSRange) {
            storage.enumerateAttribute(.font, in: r) { value, sub, _ in
                let shown = (value as? NSFont) ?? style.body
                storage.addAttributes(isActive ? [.foregroundColor: style.markerActive, .markdownMarker: shown]
                                               : [.foregroundColor: style.markerHidden, .font: style.hiddenFont,
                                                  .markdownMarker: shown], range: sub)
            }
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

    /// A bullet indented with tabs: the dash sits on its tab stop, and the space after it
    /// widens so the text is as far from the dot as a top-level bullet's. Nil for space indents.
    func nestedBulletPlacement(_ line: Substring, _ block: MarkdownStyle.Block) -> (textStart: CGFloat, kern: CGFloat)? {
        guard block.marker.count == 2, line.utf16.prefix(block.indent.upperBound).allSatisfy({ $0 == 9 }) else { return nil }
        let marker = String(line.utf16.prefix(block.marker.upperBound).dropFirst(block.marker.lowerBound)) ?? ""
        let attributes: [NSAttributedString.Key: Any] = [.font: style.body]
        let dash = NSAttributedString(string: String(marker.prefix(1)), attributes: attributes).size().width
        let whole = NSAttributedString(string: marker, attributes: attributes).size().width
        let stop = CGFloat(block.indent.count) * style.tabInterval
        let textStart = ceil(stop + dash / 2 + style.bulletTextIndent - style.bulletCenter)
        return (textStart, max(0, textStart - stop - whole))
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
        var last = ns.paragraphRange(for: NSRange(location: min(NSMaxRange(editedRange), ns.length), length: 0))
        // The next line too: a heading's space above depends on whether this line is empty.
        if NSMaxRange(last) < ns.length {
            last = NSUnionRange(last, ns.paragraphRange(for: NSRange(location: NSMaxRange(last), length: 0)))
        }
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

extension MarkdownStyler: NSTextLayoutManagerDelegate {
    /// Every paragraph lays out as a MarkdownLayoutFragment, which draws bullets and quote bars.
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        let fragment = MarkdownLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.style = style
        fragment.appearanceSource = textView
        return fragment
    }
}

/// A paragraph's layout that also draws what the Markdown stands for: a dot over a bullet's
/// (hidden) dash, and a bar down a quote over its (hidden) ">". The characters stay as typed.
nonisolated final class MarkdownLayoutFragment: NSTextLayoutFragment {
    // Set and read on the main thread only: TextKit lays out and draws the editor there.
    nonisolated(unsafe) var style: EditorStyle?
    /// The view whose appearance (light or dark) the colors resolve in.
    nonisolated(unsafe) weak var appearanceSource: NSView?

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        // Drawing runs on the main thread, where TextKit lays out the editor.
        nonisolated(unsafe) let fragment = self, cg = context
        MainActor.assumeIsolated { fragment.drawMarkdown(at: point, in: cg) }
    }

    @MainActor private func drawMarkdown(at point: CGPoint, in context: CGContext) {
        guard let style else { return }
        guard let paragraph = textElement as? NSTextParagraph else { return }
        let text = paragraph.attributedString
        let whole = NSRange(location: 0, length: text.length)
        var bullets: [Int] = [], quotes: [Int] = [], tasks: [(NSRange, done: Bool)] = []
        text.enumerateAttribute(.markdownBullet, in: whole) { value, r, _ in if value != nil { bullets.append(r.location) } }
        text.enumerateAttribute(.markdownQuoteBar, in: whole) { value, r, _ in if value != nil { quotes.append(r.location) } }
        text.enumerateAttribute(.markdownTask, in: whole) { value, r, _ in if let done = value as? Bool { tasks.append((r, done)) } }
        guard !bullets.isEmpty || !quotes.isEmpty || !tasks.isEmpty, let first = textLineFragments.first else { return }
        let lines = textLineFragments
        let appearance = appearanceSource?.effectiveAppearance ?? NSAppearance.currentDrawing()
        /// The marker character's left edge and width on the first line, in the context.
        func span(_ index: Int, length: Int = 1) -> (x: CGFloat, width: CGFloat) {
            let x = first.locationForCharacter(at: index).x
            let end = index + length
            let next = end <= NSMaxRange(first.characterRange) ? first.locationForCharacter(at: end).x : x
            return (point.x + first.typographicBounds.minX + x, max(0, next - x))
        }
        let baseline = point.y + first.typographicBounds.minY + first.glyphOrigin.y
        appearance.performAsCurrentDrawingAppearance {
            context.saveGState()
            for index in bullets {
                let (x, width) = span(index)
                let d = style.bulletDiameter
                let center = CGPoint(x: x + width / 2, y: baseline - style.body.xHeight / 2)
                context.setFillColor(style.bullet.cgColor)
                context.fillEllipse(in: CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d))
            }
            for index in quotes {
                let (x, width) = span(index)
                let top = point.y + first.typographicBounds.minY
                let bottom = point.y + (lines.last?.typographicBounds.maxY ?? first.typographicBounds.maxY)
                let w = style.quoteBarWidth
                context.setFillColor(style.quoteBar.cgColor)
                let bar = CGRect(x: x + width / 2 - w / 2, y: top, width: w, height: bottom - top)
                context.addPath(CGPath(roundedRect: bar, cornerWidth: w / 2, cornerHeight: w / 2, transform: nil))
                context.fillPath()
            }
            for (range, done) in tasks {
                let (x, width) = span(range.location, length: range.length)
                let size = style.taskBoxSize
                let box = CGRect(x: x + (width - size) / 2, y: baseline - style.body.capHeight / 2 - size / 2,
                                 width: size, height: size)
                let corner = Metric.buttonCorner / 2
                if done {
                    context.setFillColor(style.taskDone.cgColor)
                    context.addPath(CGPath(roundedRect: box, cornerWidth: corner, cornerHeight: corner, transform: nil))
                    context.fillPath()
                    context.setStrokeColor(style.taskCheck.cgColor)
                    context.setLineWidth(1.75)
                    context.setLineCap(.round)
                    context.setLineJoin(.round)
                    context.move(to: CGPoint(x: box.minX + size * 0.27, y: box.minY + size * 0.52))
                    context.addLine(to: CGPoint(x: box.minX + size * 0.43, y: box.minY + size * 0.68))
                    context.addLine(to: CGPoint(x: box.minX + size * 0.74, y: box.minY + size * 0.34))
                    context.strokePath()
                } else {
                    context.setStrokeColor(style.taskBox.cgColor)
                    context.setLineWidth(1.25)
                    let inset = box.insetBy(dx: 0.625, dy: 0.625)
                    context.addPath(CGPath(roundedRect: inset, cornerWidth: corner, cornerHeight: corner, transform: nil))
                    context.strokePath()
                }
            }
            context.restoreGState()
        }
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
        textLayoutManager?.delegate = styler
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

    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: KitType.nsFont(.monoSmall),
        .foregroundColor: Ink.appKit(.textSecondary),
    ]

    /// One timestamp: its text, where it draws, its baseline, and the baseline of the line's
    /// first row (both in this view's coordinates).
    struct Stamp {
        var text: NSString
        var point: NSPoint
        var baseline: CGFloat
        var lineBaseline: CGFloat
    }

    /// The stamps for the lines that touch `rect`. Each is placed from its line's first text
    /// line fragment (the layout fragment's origin plus the line's own origin), and aligned by
    /// baseline, so the line spacing (a fixed shorter line plus `lineSpacing`, which makes the
    /// typographic height about 21.5 instead of the 24 pt pitch) cannot shift it.
    func stamps(in rect: NSRect) -> [Stamp] {
        guard let textView, let times = textView.marginTimes, !times.isEmpty,
              let layout = textView.textLayoutManager else { return [] }
        let font = Self.attributes[.font] as? NSFont ?? KitType.nsFont(.monoSmall)
        let origin = textView.textContainerOrigin
        let right = bounds.maxX - textView.styler.style.leadingInset
        let start = layout.textViewportLayoutController.viewportRange?.location ?? layout.documentRange.location
        var found: [Stamp] = []
        layout.enumerateTextLayoutFragments(from: start, options: []) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
            if frame.minY > rect.maxY { return false }
            guard frame.maxY >= rect.minY, let paragraph = fragment.textElement as? NSTextParagraph else { return true }
            var line = paragraph.attributedString.string
            if line.hasSuffix("\n") { line.removeLast() }
            guard let time = times.time(for: line) else { return true }
            let text = Clock.text(time) as NSString
            let size = text.size(withAttributes: Self.attributes)
            // Level with the first row: the timestamp's baseline sits on the line's baseline.
            let first = fragment.textLineFragments.first
            let lineBaseline = frame.minY + (first?.typographicBounds.minY ?? 0) + (first?.glyphOrigin.y ?? frame.height / 2)
            let y = lineBaseline - font.ascender
            found.append(Stamp(text: text, point: NSPoint(x: right - size.width, y: y), baseline: y + font.ascender,
                               lineBaseline: lineBaseline))
            return true
        }
        return found
    }

    override func draw(_ dirtyRect: NSRect) {
        for stamp in stamps(in: dirtyRect) {
            stamp.text.draw(at: stamp.point, withAttributes: Self.attributes)
        }
    }
}
