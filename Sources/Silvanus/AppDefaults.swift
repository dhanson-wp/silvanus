import AppKit
import Foundation

/// Every defaults read and write in the app goes through `AppDefaults.shared`,
/// including `@AppStorage(..., store: AppDefaults.shared)`.
/// Test, snapshot, and self-test runs (APP_STORE, APP_SNAPSHOT, or --selftest)
/// use their own suite, cleared at launch, so they never change the settings
/// of the copy people use and always start from the defaults.
enum AppDefaults {
    nonisolated static let testSuite = "com.derekhanson.silvanus.test"

    /// True for test, snapshot, and self-test runs.
    nonisolated static var isTest: Bool {
        let env = ProcessInfo.processInfo.environment
        return !(env["APP_STORE"] ?? "").isEmpty
            || !(env["APP_SNAPSHOT"] ?? "").isEmpty
            || CommandLine.arguments.contains("--selftest")
    }

    static let shared: UserDefaults = {
        guard isTest, let suite = UserDefaults(suiteName: testSuite) else { return .standard }
        suite.removePersistentDomain(forName: testSuite)
        return suite
    }()
}

/// What Settings > Appearance offers: follow the Mac, or always light or dark.
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// nil follows the Mac.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Makes every window of the app use this appearance.
    @MainActor func apply() {
        NSApplication.shared.appearance = nsAppearance
    }
}

/// The settings that have a Settings pane. Reads and writes go through `AppDefaults.shared`.
extension AppDefaults {
    static let appearanceKey = "appearance.mode"
    static let showInDockKey = "general.showInDock"
    static let settingsPaneKey = "settings.pane"
    static let meNameKey = "meName"

    /// The name the transcript shows for the mic side. "Me" until a name is set.
    static var meName: String {
        let name = shared.string(forKey: meNameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Me" : name
    }

    static var appearance: AppearanceChoice {
        get { AppearanceChoice(rawValue: shared.string(forKey: appearanceKey) ?? "") ?? .system }
        set { shared.set(newValue.rawValue, forKey: appearanceKey) }
    }

    /// Saved only for now; the Dock icon follows it once that behavior lands.
    static var showInDock: Bool {
        get { shared.object(forKey: showInDockKey) as? Bool ?? true }
        set { shared.set(newValue, forKey: showInDockKey) }
    }
}
