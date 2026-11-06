import AppKit
import SilvanusKit
import SwiftUI

/// KIT.md "Transcript view", speaker block: its measured spacing, by cap top.
extension Metric {
    /// A block is indented 8 from the text start (x 229).
    static let blockIndent: CGFloat = 8
    /// The timestamp sits 8 after the speaker label.
    static let timestampGap: CGFloat = 8
    /// From the speaker label's cap top to the paragraph's.
    static let labelToParagraphCaps: CGFloat = 28.5
    /// From a block's last line's cap top to the next block's label cap top.
    static let blockToBlockCaps: CGFloat = 40
    /// The hover fill reaches 4 past the block on every side.
    static let blockHoverOutset: CGFloat = 4
    /// The current word's fill.
    static let wordCorner: CGFloat = 3
}

extension KitType {
    /// From the top of a one-line Text set in this role to its cap top.
    var capTopInLine: CGFloat { extraLeading / 2 + nsFont.ascender - nsFont.capHeight }
    /// A one-line Text's height in this role.
    var lineBox: CGFloat { NSLayoutManager().defaultLineHeight(for: nsFont) + extraLeading }
}

/// One speaker's turn in the Transcript view, from KIT.md "Transcript view": the speaker label
/// (`label`, medium, `accentText`; adapted to medium so a midnight label separates from
/// midnight text in light), the timestamp 8 after it (`monoSmall`, `textSecondary`, a button
/// that plays from there), then the paragraph (`transcript`, `text`) with its cap top 28.5
/// below the label's.
///
/// The paragraph is one Text: each word is a run of one AttributedString, and its own link
/// (`silvanus-word:<index>`, with its trailing space), so the Text's own layout hit-tests a
/// click to its word and no word needs a view. A word under 0.6 confidence gets a 1 pt dotted underline in
/// `textSecondary`; the current word gets a fill (adapted: `divider`, since Silvanus's
/// `selection` is the canvas's own color).
///
/// | State | Paragraph |
/// | rest | text |
/// | playing | the current word gets the fill |
/// | hover | controlHover at 50% behind the block, corner 8, 4 past it (selection is the canvas) |
/// | focused | 2 pt focus ring around the block; Return or Space plays from the block's start |
struct TranscriptBlock: View {
    let block: TranscriptLayout.Block
    /// The current word's index in the whole transcript, when it's in this block.
    var selectedWord: Int?
    /// A word or the timestamp was clicked: its index in the whole transcript.
    var select: (Int) -> Void = { _ in }

    @Environment(\.forcedPartState) private var forced
    @FocusState private var focused: Bool
    @State private var hovering = false

    private var state: PartState {
        forced ?? (focused ? .focused : hovering ? .hover : selectedWord != nil ? .selected : .rest)
    }

    /// The gap between blocks that puts the next label's cap top 40 below this block's last
    /// line's cap top.
    /// Worked out once from the fonts.
    static let spacing: CGFloat = {
        let lastLineBelowCap = KitType.transcript.lineBox - KitType.transcript.capTopInLine
        return Metric.blockToBlockCaps - lastLineBelowCap - KitType.label.capTopInLine
    }()

    private static let labelToParagraph: CGFloat =
        Metric.labelToParagraphCaps - (KitType.label.lineBox - KitType.label.capTopInLine) - KitType.transcript.capTopInLine

    var body: some View {
        VStack(alignment: .leading, spacing: Self.labelToParagraph) {
            HStack(alignment: .firstTextBaseline, spacing: Metric.timestampGap) {
                Text(block.speaker)
                    .kitType(.label)
                    .fontWeight(.medium)
                    .foregroundStyle(Ink.accentText)
                    .lineLimit(1)
                Button {
                    select(block.firstWord)
                } label: {
                    Text(Clock.text(block.start))
                        .kitType(.monoSmall)
                        .foregroundStyle(Ink.textSecondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Play from \(Clock.text(block.start))")
            }
            // Snapshot runs click the timestamp and a word from these frames.
            .gridArea("transcriptLabel-\(block.id)", inset: 0)
            Text(Self.paragraph(block, selected: selectedWord))
                .kitType(.transcript)
                .foregroundStyle(Ink.text)
                // Word links take the text's color; only the underline marks a word.
                .tint(Ink.text)
                .fixedSize(horizontal: false, vertical: true)
                .gridArea("transcriptText-\(block.id)", inset: 0)
                .environment(\.openURL, OpenURLAction { url in
                    if let index = TranscriptLayout.wordIndex(link: url) { select(index) }
                    return .handled
                })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Metric.rowCorner)
            ZStack {
                if state == .hover { shape.fill(Ink.controlHover.opacity(0.5)) }
                if state == .focused { shape.strokeBorder(Ink.focus, lineWidth: Metric.focusRing) }
            }
            .padding(-Metric.blockHoverOutset)
        }
        // Keyboard focus only (Tab with keyboard navigation on): a click selects a word, not the block.
        .focusable(interactions: .activate)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.return, .space]) { _ in
            select(block.firstWord)
            return .handled
        }
        .onHover { inside in
            withAnimation(Motion.hover) { hovering = inside }
        }
        // One element for VoiceOver, not one link per word.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(block.speaker), \(Clock.spoken(block.start)): \(block.text)")
        .accessibilityAction { select(block.firstWord) }
        .accessibilityAction(named: "Play from \(Clock.spoken(block.start))") { select(block.firstWord) }
    }

    /// The paragraph's text (TranscriptLayout.paragraph: each word and its trailing space is
    /// one link), with low-confidence words underlined and the current word filled.
    static func paragraph(_ block: TranscriptLayout.Block, selected: Int?) -> AttributedString {
        let low = Text.LineStyle(pattern: .dot, color: Ink.textSecondary)
        return TranscriptLayout.paragraph(block) { index, word, run in
            if TranscriptLayout.isLowConfidence(word) { run.underlineStyle = low }
            if index == selected { run.backgroundColor = Ink.divider }
        }
    }
}
