import Foundation
import SilvanusKit

/// Headless Granola import for agents and the first real run.
///   APP_STORE=/tmp/Silvanus-import APP_IMPORT_GRANOLA=<archive dir> \
///     ~/Library/Developer/Silvanus/Silvanus.app/Contents/MacOS/Silvanus
/// Reads `<archive>/raw/*.json`, `mcp-gaps/*.json`, `folders.json`, and `mcp-folders.json` (docs/MIGRATION.md), writes
/// meeting folders under APP_STORE, prints `imported N, skipped M, failed K` and each
/// `failed: <file>: <reason>`, then quits. APP_ME_NAME names the microphone side (default: the Settings name, else "Me").
/// Refuses unless APP_STORE is a folder under /tmp, so a trial run can't touch real meetings.
enum ImportCommand {
    static var requested: Bool {
        !(ProcessInfo.processInfo.environment["APP_IMPORT_GRANOLA"] ?? "").isEmpty
    }

    /// Runs the import when asked; returns the exit code.
    static func runIfRequested() -> Int32? {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["APP_IMPORT_GRANOLA"], !path.isEmpty else { return nil }
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isScratch else {
            print("IMPORT refused: set APP_STORE to a folder under /tmp")
            return 1
        }
        let archive = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: archive.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            print("IMPORT failed: no archive folder at \(archive.lastPathComponent)")
            return 1
        }
        let me = env["APP_ME_NAME"].flatMap { $0.isEmpty ? nil : $0 } ?? AppDefaults.meName
        let result = GranolaImport.run(archive: archive, library: MeetingLibrary(root: Store.root), me: me)
        print(result.summary)
        for f in result.failures { print("failed: \(f.file): \(f.reason)") }
        return result.failed.isEmpty ? 0 : 1
    }
}
