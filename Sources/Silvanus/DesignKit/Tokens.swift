import AppKit
import SilvanusKit
import SwiftUI

// The design kit's tokens, from design/KIT.md "Tokens", in three layers:
//   1. KitPalette: raw colors. Only this file reads it.
//   2. Ink: what a color means, light and dark, for the active ColorSet. Parts read only this.
//   3. Metric and Motion: sizes and curves. Type is in KitType.swift, icons in KitIcon.swift.

/// A light and a dark value, each 0xRRGGBB.
struct InkPair: Equatable {
    let light: UInt32
    let dark: UInt32

    init(light: UInt32, dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    /// The same value in both themes.
    init(_ both: UInt32) {
        self.init(light: both, dark: both)
    }

    func value(dark: Bool) -> UInt32 { dark ? self.dark : light }
}

// MARK: - Layer 1: palette

/// Raw colors. Only this file reads them.
enum KitPalette {
    // Silvanus, the scribe. The named colors and theme tokens come from the bundled
    // brand-colors.json through Brand.palette. The KIT.md values stand in when the file is
    // missing (a bare `swift run`); `missingFromBrand` lists any that did, and the self-test
    // fails on them.
    private static let brand = Brand.palette

    static let midnight = named("midnight", 0x17142C)
    static let raisedMidnight = named("raisedMidnight", 0x252039)
    static let ivory = named("ivory", 0xF5EDDF)
    static let paper = named("paper", 0xFFFBF5)
    static let parchment = named("parchment", 0xE6DAC5)
    static let mutedInk = named("mutedInk", 0x6D6674)
    static let mutedIvory = named("mutedIvory", 0xBCB4C5)
    static let gold = named("gold", 0xC8AA73)
    /// The recording fill. Ours, not the brand's: an ivory label on it reads 5.65:1.
    static let recordRed: UInt32 = 0xB42318
    /// Recording text on dark surfaces. Ours: 6.84:1 on raisedMidnight.
    static let recordRedLight: UInt32 = 0xFF8A80

    // The brand's theme tokens, light and dark.
    static let background = theme("background", light: ivory, dark: midnight)
    static let surface = theme("surface", light: paper, dark: raisedMidnight)
    static let navigation = theme("navigation", light: midnight, dark: midnight)
    static let text = theme("text", light: midnight, dark: ivory)
    static let textSecondary = theme("textSecondary", light: mutedInk, dark: mutedIvory)
    static let primaryControl = theme("primaryControl", light: midnight, dark: ivory)
    static let onPrimary = theme("onPrimary", light: ivory, dark: midnight)
    static let accent = theme("accent", light: gold, dark: gold)
    static let divider = theme("divider", light: parchment, dark: mutedInk)
    static let focus = theme("focus", light: midnight, dark: gold)

    /// The brand ground the sidebar sits on. KIT.md puts it on `background` (ivory in light),
    /// one step darker than the paper canvas, not the brand's midnight `navigation`, which
    /// would turn the light theme's sidebar dark. Change this one line to flip it.
    enum SidebarGround { case background, navigation }
    static let sidebarGround = SidebarGround.background
    static var sidebar: InkPair { sidebarGround == .background ? background : navigation }

    /// Silvanus colors that fell back to the KIT.md value because the brand file lacked them.
    static var missingFromBrand: [String] {
        let names = ["midnight", "raisedMidnight", "ivory", "paper", "parchment", "mutedInk", "mutedIvory", "gold"]
            .filter { brand.hex(named: $0) == nil }
        let tokens = ["background", "surface", "navigation", "text", "textSecondary", "primaryControl",
                      "onPrimary", "accent", "divider", "focus"]
            .flatMap { token in [false, true].compactMap { brand.hex(token, dark: $0) == nil ? "\(token)/\($0 ? "dark" : "light")" : nil } }
        return names + tokens
    }

    private static func named(_ name: String, _ fallback: UInt32) -> UInt32 {
        brand.hex(named: name) ?? fallback
    }

    private static func theme(_ token: String, light: UInt32, dark: UInt32) -> InkPair {
        InkPair(light: brand.hex(token) ?? light, dark: brand.hex(token, dark: true) ?? dark)
    }

    // Reference, measured. Pixel compare only.
    static let refSidebar = InkPair(light: 0xFAFAF9, dark: 0x1F1B19)
    static let refCanvas = InkPair(light: 0xFFFFFF, dark: 0x2D2825)
    static let refDivider = InkPair(light: 0xE7E5E4, dark: 0x4C4743)
    static let refText = InkPair(light: 0x1B1917, dark: 0xFAFAF9)
    static let refSecondary = InkPair(light: 0x79736D, dark: 0x928B86)
    static let refTertiary = InkPair(light: 0x9A9592, dark: 0x77716C)
    static let refChipText = InkPair(light: 0x525252, dark: 0xD4D4D4)
    static let refSelection = InkPair(light: 0xF0F0EF, dark: 0x443F3C)
    static let refPillTrack = InkPair(light: 0xE8E8E8, dark: 0x3A3532)
    static let refPillSegment = InkPair(light: 0xFFFFFF, dark: 0x443F3C)
    static let refBarBorder = InkPair(light: 0xEEEDEC, dark: 0x433D3A)
    static let refRule = InkPair(light: 0xFC5156, dark: 0xBD4E50)
    static let refSpeaker = InkPair(light: 0xB4445C, dark: 0xF0788C)
    static let refControlOn = InkPair(0x2D2825)
    static let refControlKnob = InkPair(0xFAFAF9)
    static let refSettingsPane = InkPair(light: 0xFFFFFF, dark: 0x443F3C)
    static let refSettingsSelected = InkPair(light: 0xE7E7E4, dark: 0x3E3A37)
    static let refSearchField = InkPair(light: 0xF5F5F4, dark: 0x312D2A)
}

/// A named palette color, for the gallery's swatches.
struct Swatch: Identifiable {
    let name: String
    let pair: InkPair
    var id: String { name }

    /// The raw colors of a set, in KIT.md order.
    static func palette(_ set: ColorSet) -> [Swatch] {
        typealias P = KitPalette
        switch set {
        case .silvanus:
            return [("midnight", InkPair(P.midnight)), ("raisedMidnight", InkPair(P.raisedMidnight)),
                    ("ivory", InkPair(P.ivory)), ("paper", InkPair(P.paper)), ("parchment", InkPair(P.parchment)),
                    ("mutedInk", InkPair(P.mutedInk)), ("mutedIvory", InkPair(P.mutedIvory)), ("gold", InkPair(P.gold)),
                    ("recordRed", InkPair(P.recordRed)), ("recordRedLight", InkPair(P.recordRedLight))]
                .map { Swatch(name: $0.0, pair: $0.1) }
        case .reference:
            return [("refSidebar", P.refSidebar), ("refCanvas", P.refCanvas), ("refDivider", P.refDivider),
                    ("refText", P.refText), ("refSecondary", P.refSecondary), ("refTertiary", P.refTertiary),
                    ("refChipText", P.refChipText), ("refSelection", P.refSelection), ("refPillTrack", P.refPillTrack),
                    ("refPillSegment", P.refPillSegment), ("refBarBorder", P.refBarBorder), ("refRule", P.refRule),
                    ("refSpeaker", P.refSpeaker), ("refControlOn", P.refControlOn), ("refControlKnob", P.refControlKnob),
                    ("refSettingsPane", P.refSettingsPane), ("refSettingsSelected", P.refSettingsSelected),
                    ("refSearchField", P.refSearchField)]
                .map { Swatch(name: $0.0, pair: $0.1) }
        }
    }
}

// MARK: - Layer 2: meaning

/// Every meaning token in design/KIT.md "Meaning", with its value in each set.
enum InkToken: String, CaseIterable {
    case background, sidebar, canvas, text, textSecondary, textTertiary, divider, selection
    case pillTrack, pillSegment, accent, accentText, focus, primaryControl, onPrimary
    case controlHover
    case recording, onRecording, recordingText

    /// The light and dark value in a set.
    func pair(_ set: ColorSet) -> InkPair {
        switch set {
        case .silvanus: silvanus
        // The reference has no focus or recording colors (n/a in KIT.md); it borrows Silvanus's.
        case .reference: reference ?? silvanus
        }
    }

    func rgb(_ set: ColorSet, dark: Bool) -> RGB {
        RGB(hex: pair(set).value(dark: dark))
    }

    /// The token in the active set, following light and dark mode.
    var color: Color {
        let pair = pair(.active)
        return Color(light: pair.light, dark: pair.dark)
    }

    private var silvanus: InkPair {
        typealias P = KitPalette
        return switch self {
        case .background: P.background
        case .sidebar: P.sidebar
        case .canvas: P.surface
        case .text: P.text
        case .textSecondary: P.textSecondary
        // Only unselected pill icons use it; KIT.md gives it the secondary values.
        case .textTertiary: P.textSecondary
        case .divider: P.divider
        // Paper, not parchment: secondary text on parchment is 4.00:1.
        case .selection: InkPair(light: P.paper, dark: P.raisedMidnight)
        // Selection matches the canvas, so a control on the canvas hovers one step darker.
        case .controlHover: InkPair(light: P.ivory, dark: P.midnight)
        case .pillTrack: InkPair(light: P.parchment, dark: P.midnight)
        case .pillSegment: InkPair(light: P.paper, dark: P.raisedMidnight)
        // Gold is fill only.
        case .accent: P.accent
        // Gold text is 2.15:1 on paper, so light accent text is midnight.
        case .accentText: InkPair(light: P.midnight, dark: P.gold)
        case .focus: P.focus
        case .primaryControl: P.primaryControl
        case .onPrimary: P.onPrimary
        case .recording: InkPair(P.recordRed)
        case .onRecording: InkPair(P.ivory)
        // recordRed is 2.38:1 on raisedMidnight, so dark uses recordRedLight.
        case .recordingText: InkPair(light: P.recordRed, dark: P.recordRedLight)
        }
    }

    private var reference: InkPair? {
        typealias P = KitPalette
        return switch self {
        case .background, .sidebar: P.refSidebar
        case .canvas: P.refCanvas
        case .text: P.refText
        case .textSecondary: P.refSecondary
        case .textTertiary: P.refTertiary
        case .divider: P.refDivider
        case .selection, .controlHover: P.refSelection
        case .pillTrack: P.refPillTrack
        case .pillSegment: P.refPillSegment
        case .accent: P.refRule
        case .accentText: P.refSpeaker
        case .primaryControl: P.refControlOn
        case .onPrimary: P.refControlKnob
        case .focus, .recording, .onRecording, .recordingText: nil
        }
    }

    /// Silvanus colors that fell back to the KIT.md value because the brand file lacked them.
    static var missingFromBrand: [String] { KitPalette.missingFromBrand }

    /// Every pair KIT.md uses as text on a surface. Each must read at 4.5:1 in the Silvanus
    /// set, light and dark (the self-test checks). textTertiary is left out: it colors icons
    /// on the pill track, never text.
    static let textPairs: [(text: InkToken, on: InkToken)] = {
        let grounds: [InkToken] = [.background, .sidebar, .canvas, .selection, .controlHover]
        let onGrounds: [InkToken] = [.text, .textSecondary, .accentText, .recordingText]
        var pairs: [(text: InkToken, on: InkToken)] = []
        for text in onGrounds {
            for ground in grounds { pairs.append((text, ground)) }
        }
        pairs.append((.text, .pillSegment))
        pairs.append((.onPrimary, .primaryControl))
        pairs.append((.onRecording, .recording))
        return pairs
    }()
}

/// What each color means. Parts read only these. Values follow light and dark mode and the
/// active ColorSet (`APP_COLORS`); see design/KIT.md "Meaning" for where each is used.
enum Ink {
    static let background = InkToken.background.color
    static let sidebar = InkToken.sidebar.color
    static let canvas = InkToken.canvas.color
    static let text = InkToken.text.color
    static let textSecondary = InkToken.textSecondary.color
    static let textTertiary = InkToken.textTertiary.color
    static let divider = InkToken.divider.color
    static let selection = InkToken.selection.color
    /// Hover and pressed fills for controls on the canvas, where `selection` wouldn't show.
    static let controlHover = InkToken.controlHover.color
    static let pillTrack = InkToken.pillTrack.color
    static let pillSegment = InkToken.pillSegment.color
    /// Fill only: never text or a focus ring.
    static let accent = InkToken.accent.color
    static let accentText = InkToken.accentText.color
    static let focus = InkToken.focus.color
    static let primaryControl = InkToken.primaryControl.color
    static let onPrimary = InkToken.onPrimary.color
    static let recording = InkToken.recording.color
    static let onRecording = InkToken.onRecording.color
    static let recordingText = InkToken.recordingText.color
}

extension Ink {
    /// A token as an AppKit color that follows light and dark mode, for text the kit draws
    /// through AppKit (the notes canvas). `alpha` below 1 tints with the same token.
    static func appKit(_ token: InkToken, alpha: CGFloat = 1) -> NSColor {
        let pair = token.pair(.active)
        return NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? pair.dark : pair.light, alpha: alpha)
        }
    }
}

// MARK: - Layer 3: scales

/// Sizes from design/KIT.md "Metric", in points.
enum Metric {
    static let windowDefault = CGSize(width: 910, height: 600)
    /// The smallest the window goes: the header controls still clear the traffic lights.
    static let windowMinimum = CGSize(width: 720, height: 480)
    /// Header controls are `controlHeight` tall at y 9.
    static let headerHeight: CGFloat = 46
    static let controlHeight: CGFloat = 28
    /// Header controls' top edge: centered in the 46 pt header.
    static let controlY: CGFloat = 9
    /// KIT.md "Window": the close button's center, from the window's top left; the others
    /// follow `trafficLightPitch` apart on the same line.
    static let trafficLightFirst = CGPoint(x: 19, y: 23)
    static let trafficLightPitch: CGFloat = 23
    /// KIT.md "Sidebar header row": the first icon button's center x (hide sidebar), then
    /// one every `sidebarHeaderPitch`.
    static let sidebarHeaderFirstX: CGFloat = 94
    static let sidebarHeaderPitch: CGFloat = 28
    /// Then a `hairline` divider at x 208.
    static let sidebarWidth: CGFloat = 208
    static let canvasX: CGFloat = 209
    static let canvasCorner: CGFloat = 10
    /// Canvas text and header start: 12 after the canvas edge.
    static let contentX: CGFloat = 221
    static let contentTrailing: CGFloat = 12
    static let sidebarRowInset: CGFloat = 4
    /// The first letter's ink lands at x 16.5, as measured: the glyph's side bearing adds half a point.
    static let sidebarTextX: CGFloat = 16
    static let rowCorner: CGFloat = 8
    static let meetingRowPitch: CGFloat = 54
    /// A meeting row with a folder line: the line adds 18.
    static let meetingRowPitchFolder: CGFloat = 72
    static let folderRowPitch: CGFloat = 28
    static let iconButton: CGFloat = 28
    static let iconButtonCorner: CGFloat = 7
    static let buttonCorner: CGFloat = 6
    static let hairline: CGFloat = 1
    /// KIT.md "focused" states: a 2 pt ring.
    static let focusRing: CGFloat = 2
    /// Dashed card dividers.
    static let dashedHairline: CGFloat = 0.5
}

/// Curves from design/KIT.md "Motion". Not measurable from stills; these are our defaults.
enum Motion {
    /// Hover fills.
    static let hover = Animation.easeOut(duration: 0.12)
    /// The view pill's segment slide and row selection.
    static let select = Animation.easeOut(duration: 0.18)
    /// The recording pill appearing and growing.
    static let pill = Animation.spring(duration: 0.3, bounce: 0)
}
