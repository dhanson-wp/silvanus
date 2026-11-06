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

    /// The accent from the bundled `brand-colors.json` (`{"accent": "#RRGGBB"}`),
    /// else the accent the theme ships with (`ThemeStore.defaultID`).
    static var accent: Color {
        if let hex = accentHex(in: Bundle.main.url(forResource: "brand-colors", withExtension: "json")) {
            return Color(hex: hex)
        }
        return Theme.all.first { $0.id == ThemeStore.defaultID }?.accent ?? .accentColor
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

/// The About window: the icon, the name, the version.
struct BrandAboutView: View {
    var body: some View {
        VStack(spacing: Space.sm) {
            Image(nsImage: Brand.appIcon)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Silvanus")
                .font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1")")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(Space.xl)
        .frame(width: 280)
    }
}
