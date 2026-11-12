import Observation
import Sparkle
import SwiftUI

/// In-app updates, through Sparkle. A release build (`./build.sh --release`) carries the feed
/// and the public update key in Info.plist; Silvanus checks once a day and asks before
/// installing anything. Dev builds, tests, snapshots, and the self-test leave the updater off.
@Observable
final class Updates {
    static let shared = Updates()

    /// Nil when updates are off for this build.
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    /// Mirrors Sparkle's own setting, so Settings can show it.
    var checksAutomatically: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = checksAutomatically }
    }

    var isAvailable: Bool { controller != nil }

    private init() {
        checksAutomatically = false
        guard Self.configured, !Store.isOverridden, !SelfTest.requested else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        checksAutomatically = controller?.updater.automaticallyChecksForUpdates ?? false
    }

    /// Starts the updater. Called once the app has launched.
    func start() { _ = controller }

    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    /// True when this build carries the update feed and key. Plain HTTP is only for a local
    /// test feed on this Mac.
    static var configured: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let text = info["SUFeedURL"] as? String, let feed = URL(string: text), let host = feed.host,
              let key = info["SUPublicEDKey"] as? String, !key.isEmpty else { return false }
        return feed.scheme == "https" || (feed.scheme == "http" && ["127.0.0.1", "localhost"].contains(host))
    }

    /// The footnote under the setting.
    var footnote: String {
        isAvailable ? "Silvanus checks once a day and asks before installing anything."
                    : "Updates are off in builds made from source. Pull and run ./build.sh to update."
    }
}

/// Silvanus > Check for Updates…, under About.
struct UpdatesCommand: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Updates.shared.checkForUpdates() }
                .disabled(!Updates.shared.isAvailable)
        }
    }
}
