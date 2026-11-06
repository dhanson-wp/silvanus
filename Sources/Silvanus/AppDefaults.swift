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
