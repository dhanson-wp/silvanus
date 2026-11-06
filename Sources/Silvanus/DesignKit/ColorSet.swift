import Foundation

/// Which colors the kit draws with (design/KIT.md "Tokens").
///   APP_COLORS=reference Silvanus   the reference colors, for the pixel-compare build
/// Without it, Silvanus colors: the scribe palette, which is what ships.
enum ColorSet: String, CaseIterable {
    /// The scribe palette from the brand files.
    case silvanus
    /// The measured reference colors. Pixel compare only; never ships.
    case reference

    /// The set this run uses, read once from `APP_COLORS`. Anything but "reference" is Silvanus.
    static let active: ColorSet = ColorSet(rawValue: ProcessInfo.processInfo.environment["APP_COLORS"] ?? "") ?? .silvanus
}
