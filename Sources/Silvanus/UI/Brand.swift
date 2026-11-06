import AppKit
import SwiftUI

/// Where the brand shows. Views and the app read the icon, the menu bar glyphs,
/// and the brand accent from here and never name a brand file. The files come
/// from `Brand/` through `tools/brand.sh`, which `build.sh` runs and copies into
/// the bundle's Resources. Without them (a bare `swift run`, unit tests) each
/// property falls back to something drawn here, so nothing is ever missing.
enum Brand {
    /// The Dock, Finder, and About icon.
    static var appIcon: NSImage {
        NSImage(named: "AppIcon") ?? NSApp?.applicationIconImage ?? NSImage(size: NSSize(width: 1024, height: 1024))
    }

    /// Menu bar glyphs are 18 pt squares (Apple's size, not a layout spacing).
    static let menuBarSize = NSSize(width: 18, height: 18) // grid: ok menu bar glyph size

    /// The menu bar glyph while idle: a template image, 18 pt.
    static var menuBarGlyph: NSImage { glyph("menubar", filled: false) }

    /// The menu bar glyph while recording: a template image, 18 pt.
    static var menuBarRecordingGlyph: NSImage { glyph("menubar-recording", filled: true) }

    /// The accent from the bundled `brand-colors.json` (`{"accent": "#RRGGBB"}`), else the
    /// kit's accent (`Ink.accent`).
    static var accent: Color {
        if let hex = accentHex(in: Bundle.main.url(forResource: "brand-colors", withExtension: "json")) {
            return Color.rgb(hex)
        }
        return Ink.accent
    }

    /// Reads the `accent` value of a brand colors file: "#RRGGBB" or "RRGGBB". nil when
    /// the file is missing or the value is not a six-digit hex color.
    static func accentHex(in file: URL?) -> UInt32? {
        guard let file, let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["accent"] as? String else { return nil }
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.count == 6 else { return nil }
        return UInt32(digits, radix: 16)
    }

    /// The brand palette from the bundled `brand-colors.json`: theme tokens (`background`,
    /// `text`, `accent`, ...) by name for the light and dark themes. Empty when the file is
    /// missing. The design kit reads it (`DesignKit/Tokens.swift`); views never do.
    static var palette: BrandPalette {
        BrandPalette(file: Bundle.main.url(forResource: "brand-colors", withExtension: "json"))
    }

    private static func glyph(_ name: String, filled: Bool) -> NSImage {
        let image: NSImage
        if let bundled = NSImage(named: name) {
            image = bundled
        } else {
            image = NSImage(size: menuBarSize, flipped: false) { rect in
                let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 2.75, dy: 2.75))
                NSColor.black.set()
                if filled { circle.fill() } else { circle.lineWidth = 1.5; circle.stroke() }
                return true
            }
        }
        image.size = menuBarSize
        image.isTemplate = true
        return image
    }
}

/// The brand's named colors and its light and dark theme tokens (`Brand/colors.json`).
/// A theme maps each token name to a color name; `color(_:dark:)` resolves it to a `Color`.
struct BrandPalette {
    private let colors: [String: String]
    private let light: [String: String]
    private let dark: [String: String]

    init(file: URL?) {
        let json = file.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let themes = json?["themes"] as? [String: [String: String]]
        colors = json?["colors"] as? [String: String] ?? [:]
        light = themes?["light"] ?? [:]
        dark = themes?["dark"] ?? [:]
    }

    /// Every token name in either theme, sorted.
    var tokens: [String] { Array(Set(light.keys).union(dark.keys)).sorted() }

    /// The token's color in the light or dark theme; nil when the token or its color is unknown.
    func color(_ token: String, dark isDark: Bool = false) -> Color? {
        hex(token, dark: isDark).map { Color.rgb($0) }
    }

    /// The token's color as 0xRRGGBB in the light or dark theme; nil when unknown.
    func hex(_ token: String, dark isDark: Bool = false) -> UInt32? {
        (isDark ? dark : light)[token].flatMap(hex(named:))
    }

    /// A named color (`midnight`, `paper`) as 0xRRGGBB; nil when unknown or not six hex digits.
    func hex(named name: String) -> UInt32? {
        guard let text = colors[name] else { return nil }
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.count == 6 else { return nil }
        return UInt32(digits, radix: 16)
    }
}

/// The About content: the icon, the name, the version. The About pane in Settings shows it
/// as is; `BrandAboutView` puts it in the About window.
struct BrandAboutContent: View {
    var body: some View {
        VStack(spacing: Space.sm) {
            Image(nsImage: Brand.appIcon)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Silvanus")
                .kitType(.title)
                .foregroundStyle(Ink.text)
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1")")
                .kitType(.label)
                .foregroundStyle(Ink.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The About window.
struct BrandAboutView: View {
    var body: some View {
        BrandAboutContent()
            .padding(Space.xl)
            .frame(width: 280)
            .background(Ink.canvas)
    }
}
