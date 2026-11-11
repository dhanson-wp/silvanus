import AppKit
import Foundation
import SilvanusKit

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
    static let promptOnMeetingKey = "general.promptOnMeeting"
    static let stopWhenCallEndsKey = "general.stopWhenCallEnds"
    static let settingsPaneKey = "settings.pane"
    static let meNameKey = "meName"
    /// The model file chosen in Settings > Summaries; unset uses the one Silvanus downloaded.
    nonisolated static let modelFileKey = "summaries.modelFile"
    /// True once Home's model card was put away: by Not Now, or because a model is in place.
    static let modelSetupHiddenKey = "summaries.setupHidden"

    /// The name the transcript shows for the mic side. "Me" until a name is set.
    static var meName: String {
        let name = shared.string(forKey: meNameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Me" : name
    }

    static let ownAddressesKey = "calendar.ownAddresses"

    /// The user's own email addresses: their calendar accounts that are addresses, saved
    /// whenever the calendars are read. They're left off a transcript's call side.
    static var ownAddresses: Set<String> {
        get { Set(shared.stringArray(forKey: ownAddressesKey) ?? []) }
        set { shared.set(newValue.sorted(), forKey: ownAddressesKey) }
    }

    /// The names a meeting's transcript shows for its two sides.
    static func speakerNames(_ info: MeetingInfo, me: String = meName) -> (me: String, them: String) {
        SpeakerNames.resolve(info: info, defaultMe: me, ownAddresses: ownAddresses)
    }

    static var appearance: AppearanceChoice {
        get { AppearanceChoice(rawValue: shared.string(forKey: appearanceKey) ?? "") ?? .system }
        set { shared.set(newValue.rawValue, forKey: appearanceKey) }
    }

    /// Settings > General > Prompt when a meeting starts. On until it's turned off.
    static var promptOnMeeting: Bool {
        get { shared.object(forKey: promptOnMeetingKey) as? Bool ?? true }
        set { shared.set(newValue, forKey: promptOnMeetingKey) }
    }

    /// Settings > General > Stop when the call ends. On until it's turned off.
    static var stopWhenCallEnds: Bool {
        get { shared.object(forKey: stopWhenCallEndsKey) as? Bool ?? true }
        set { shared.set(newValue, forKey: stopWhenCallEndsKey) }
    }

    /// Saved only for now; the Dock icon follows it once that behavior lands.
    static var showInDock: Bool {
        get { shared.object(forKey: showInDockKey) as? Bool ?? true }
        set { shared.set(newValue, forKey: showInDockKey) }
    }
}
