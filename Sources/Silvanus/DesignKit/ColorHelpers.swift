import AppKit
import SwiftUI

/// Color constructors for the kit's tokens and the brand palette. Parts never call these:
/// they read `Ink`. Light and dark values resolve through the view's appearance.
extension Color {
    /// A color from 0xRRGGBB.
    static func rgb(_ hex: UInt32) -> Color {
        Color(nsColor: NSColor(hex: hex))
    }

    /// A color with a light and a dark value. Add the two high-contrast values for Increase
    /// Contrast; they default to the normal ones.
    init(light: UInt32, dark: UInt32, highContrastLight: UInt32? = nil, highContrastDark: UInt32? = nil) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua,
                                               .accessibilityHighContrastDarkAqua]) {
            case .darkAqua: NSColor(hex: dark)
            case .accessibilityHighContrastAqua: NSColor(hex: highContrastLight ?? light)
            case .accessibilityHighContrastDarkAqua: NSColor(hex: highContrastDark ?? dark)
            default: NSColor(hex: light)
            }
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
