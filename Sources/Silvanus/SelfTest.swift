import AppKit

/// Self-test for agents: runs the app's real functions on a test folder,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/Silvanus-self ~/Library/Developer/Silvanus/Silvanus.app/Contents/MacOS/Silvanus \
///     -ApplePersistenceIgnoreState YES --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a folder in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))

            check("test runs use their own defaults", AppDefaults.isTest && AppDefaults.shared !== UserDefaults.standard)
            check("the library starts empty", model.meetings.isEmpty)
            check("All Meetings is selected", model.sidebar == .all)

            let saved = UserDefaults.standard.string(forKey: "settings.tab")
            model.settingsTab = .appearance
            check("the Settings tab is saved to the test defaults",
                  AppDefaults.shared.string(forKey: "settings.tab") == "appearance")
            check("the real defaults are left alone", UserDefaults.standard.string(forKey: "settings.tab") == saved)

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
