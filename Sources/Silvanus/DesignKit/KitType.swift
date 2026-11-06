import AppKit
import SwiftUI

/// Type roles from design/KIT.md "Type". The system font throughout, SF Mono for times.
/// Views set fonts only through `.kitType(_:)`.
enum KitType: String, CaseIterable {
    case title, heading, subheading, body, transcript
    case rowTitle, rowTitleSelected, settingTitle, button, dayHeading
    case tab, chip, label, section, meta
    case monoTime, monoSmall, dayNumber
    /// The recording controls and the Meeting detected prompt.
    case barState, barTime, barNote, promptTitle, promptBody, promptButton

    var size: CGFloat {
        switch self {
        case .title: 24
        case .heading: 20
        case .subheading: 18
        case .body, .dayHeading: 16
        case .transcript, .rowTitle, .rowTitleSelected, .settingTitle, .button: 14
        case .chip: 12.5
        case .tab, .label, .section, .monoTime: 12
        case .meta, .monoSmall, .barState, .barTime: 11
        case .dayNumber: 28
        case .promptTitle: 15
        case .promptBody: 13
        case .promptButton, .barNote: 12
        }
    }

    var weight: Font.Weight {
        switch self {
        case .title, .heading, .dayHeading: .bold
        case .subheading, .barState, .promptTitle, .promptButton: .semibold
        case .rowTitleSelected, .settingTitle, .button, .tab: .medium
        default: .regular
        }
    }

    /// The line box, as in KIT.md. Single lines get half the extra above and half below.
    var lineHeight: CGFloat {
        switch self {
        case .title: 28
        case .heading: 24
        case .subheading: 22
        case .body: 24
        case .transcript: 22.75
        case .rowTitle, .rowTitleSelected, .settingTitle, .button: 17
        case .dayHeading: 19
        case .chip: 15
        case .tab, .label, .section, .monoTime: 14
        case .meta, .monoSmall, .barState, .barTime: 13
        case .dayNumber: 28
        case .promptTitle: 21
        case .promptBody: 21
        case .promptButton: 14
        // Taller than the face's own line, so it wraps instead of clamping to one line.
        case .barNote: 16
        }
    }

    /// The weight as KIT.md writes it, for the gallery.
    var weightName: String {
        switch weight {
        case .bold: "bold"
        case .semibold: "semibold"
        case .medium: "medium"
        default: "regular"
        }
    }

    var isMonospaced: Bool { self == .monoTime || self == .monoSmall }

    /// The system face with tabular digits, so a running time doesn't jitter.
    var isTabular: Bool { self == .barTime }

    /// The settings list group label is set in capitals.
    var isUppercase: Bool { self == .section }

    var font: Font {
        let font = Font.system(size: size, weight: weight, design: isMonospaced ? .monospaced : .default)
        return isTabular ? font.monospacedDigit() : font
    }

    /// The same face for AppKit text (the notes canvas).
    var nsFont: NSFont {
        let nsWeight: NSFont.Weight = switch weight {
        case .bold: .bold
        case .semibold: .semibold
        case .medium: .medium
        default: .regular
        }
        return isMonospaced ? .monospacedSystemFont(ofSize: size, weight: nsWeight)
            : .systemFont(ofSize: size, weight: nsWeight)
    }

    /// A role's AppKit font, for text drawn through AppKit (the notes canvas).
    static func nsFont(_ role: KitType) -> NSFont { role.nsFont }

    /// Code inside a role's text: SF Mono, a little smaller so its x-height sits with the
    /// system face around it. KIT.md has no code role; this keeps code on the role's line.
    static func nsCodeFont(in role: KitType) -> NSFont {
        .monospacedSystemFont(ofSize: (role.size * 0.92).rounded(), weight: .regular)
    }

    /// Space the line box adds to the font's own line height. Zero when the font's line is
    /// already taller (dayNumber: 28 pt digits on a 28 pt line).
    var extraLeading: CGFloat { Self.leading[self] ?? 0 }

    /// True when the font's own line is taller than the role's line box (dayNumber: 28 pt
    /// digits draw a 33 pt line). Those roles are clamped to the box, so a single line takes
    /// the height KIT.md gives it.
    var clampsLine: Bool { Self.tallLine.contains(self) }

    private static let tallLine: Set<KitType> = {
        let layout = NSLayoutManager()
        return Set(allCases.filter { layout.defaultLineHeight(for: $0.nsFont) > $0.lineHeight })
    }()

    private static let leading: [KitType: CGFloat] = {
        let layout = NSLayoutManager()
        return Dictionary(uniqueKeysWithValues: allCases.map { type in
            (type, max(0, type.lineHeight - layout.defaultLineHeight(for: type.nsFont)))
        })
    }()
}

extension View {
    /// Sets a type role: font, line height, and case.
    func kitType(_ type: KitType) -> some View {
        font(type.font)
            .lineSpacing(type.extraLeading)
            .padding(.vertical, type.extraLeading / 2)
            .frame(height: type.clampsLine ? type.lineHeight : nil)
            .textCase(type.isUppercase ? .uppercase : nil)
    }
}
