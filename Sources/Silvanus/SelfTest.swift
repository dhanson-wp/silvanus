import AVFoundation
import AppKit
import SilvanusKit
import SwiftUI

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
        guard Store.isScratch else {
            print("SELFTEST refused: set APP_STORE to a folder under /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))

            check("test runs use their own defaults", AppDefaults.isTest && AppDefaults.shared !== UserDefaults.standard)
            check("the library starts empty", model.meetings.isEmpty)
            // The folder store, on the /tmp store: save, reload, trash.
            let meeting = Meeting(info: MeetingInfo(title: "Acme kickoff", start: Date(timeIntervalSince1970: 1_793_975_400),
                                                    attendees: ["Sam Rivera"]), notes: "Agenda")
            let folder = try? model.library.save(meeting)
            model.reload()
            check("a saved meeting lands in a folder under the store",
                  folder?.path.hasPrefix(Store.root.standardizedFileURL.path) == true
                  && FileManager.default.fileExists(atPath: folder?.appending(path: "meeting.json").path ?? ""))
            check("the saved meeting is listed after a reload", model.meetings.map(\.id) == [meeting.id])
            try? model.moveToTrash(meeting.id)
            model.reload()
            check("a trashed meeting is gone from the list", model.meetings.isEmpty)
            check("All Meetings is selected", model.sidebar == .all)

            // The sidebar's folders: listed once each, sorted; choosing one filters the list.
            let filed = [("Weekly sync", "Team"), ("Acme kickoff", "Clients"), ("Budget review", "Team"), ("Design review", nil)]
                .enumerated().map { index, item in
                    Meeting(info: MeetingInfo(title: item.0, start: Date(timeIntervalSince1970: 1_793_975_400 - Double(index) * 3_600),
                                              folder: item.1))
                }
            for meeting in filed { _ = try? model.library.save(meeting) }
            model.reload()
            check("the sidebar lists each folder once, sorted, with counts",
                  model.folders.map { "\($0.name) \($0.count)" } == ["Clients 1", "Team 2"],
                  model.folders.map(\.name).joined(separator: ", "))
            model.folder = "Team"
            check("choosing a folder shows only its meetings",
                  model.visibleMeetings.map(\.displayTitle) == ["Weekly sync", "Budget review"],
                  model.visibleMeetings.map(\.displayTitle).joined(separator: ", "))
            model.folder = nil
            check("All meetings shows every meeting", model.visibleMeetings.count == filed.count)
            model.folder = "Clients"
            for meeting in filed { try? model.library.moveToTrash(meeting.id) }
            model.reload()
            check("a folder with no meetings left stops filtering the list", model.folder == nil && model.folders.isEmpty)

            // The sidebar groups once per change to the meetings or folder, never per selection.
            let many = (0..<300).map { index in
                Meeting(info: MeetingInfo(id: "many-\(index)", title: "Weekly sync \(index)",
                                          start: Date().addingTimeInterval(-Double(index) * 7_200),
                                          folder: index.isMultiple(of: 3) ? "Team" : nil))
            }
            let before = model.regroupCount
            model.meetings = many
            let afterLoad = model.regroupCount
            for id in model.sidebarOrder.prefix(50) { model.selection = id }
            let afterArrows = model.regroupCount
            model.folder = "Team"
            let afterFolder = model.regroupCount
            check("300 meetings group once per data change, not per selection change",
                  afterLoad - before == 1 && afterArrows == afterLoad && afterFolder - afterArrows == 1
                  && model.sidebarOrder.count == 100,
                  "load \(afterLoad - before), 50 selections \(afterArrows - afterLoad), folder \(afterFolder - afterArrows)")
            model.folder = nil
            model.selection = nil
            model.reload()

            // Review Focus 3: a selected row's fill dims when the window is inactive.
            let active = selectionFill(appearsActive: true)
            let inactive = selectionFill(appearsActive: false)
            check("the selected row's fill dims when the window is inactive",
                  active != nil && inactive != nil && active != inactive,
                  "active \(active ?? "none"), inactive \(inactive ?? "none")")

            let saved = UserDefaults.standard.string(forKey: AppDefaults.settingsPaneKey)
            model.settingsPane = .appearance
            check("the Settings pane is saved to the test defaults",
                  AppDefaults.shared.string(forKey: AppDefaults.settingsPaneKey) == "appearance")
            check("the real defaults are left alone",
                  UserDefaults.standard.string(forKey: AppDefaults.settingsPaneKey) == saved)
            model.settingsPane = .general

            let palette = Brand.palette
            let unresolved = palette.tokens.flatMap { token in
                [false, true].compactMap { palette.color(token, dark: $0) == nil ? "\(token)/\($0 ? "dark" : "light")" : nil }
            }
            check("Brand.palette resolves every token in both themes",
                  !palette.tokens.isEmpty && unresolved.isEmpty, unresolved.joined(separator: ", "))

            // Design kit: every text-on-surface pair in design/KIT.md "Meaning" reads at 4.5:1
            // in the Silvanus set, light and dark, whatever APP_COLORS says.
            let weak = InkToken.textPairs.flatMap { pair in
                [false, true].compactMap { dark -> String? in
                    let ratio = Contrast.ratio(pair.text.rgb(.silvanus, dark: dark), pair.on.rgb(.silvanus, dark: dark))
                    return ratio < 4.5 ? "\(pair.text) on \(pair.on) \(dark ? "dark" : "light") \(String(format: "%.2f", ratio))" : nil
                }
            }
            check("every Ink text pair reads at 4.5:1 in both themes", weak.isEmpty, weak.joined(separator: ", "))
            let faint = InkToken.graphicPairs.flatMap { pair in
                [false, true].flatMap { dark in
                    [ColorSet.silvanus, ColorSet.reference].compactMap { set -> String? in
                        let ratio = Contrast.ratio(pair.graphic.rgb(set, dark: dark), pair.on.rgb(set, dark: dark))
                        return ratio < 3 ? "\(pair.graphic) on \(pair.on) \(dark ? "dark" : "light") \(String(format: "%.2f", ratio))" : nil
                    }
                }
            }
            check("every Ink graphic pair on the pill reads at 3:1 in both themes and sets", faint.isEmpty, faint.joined(separator: ", "))
            let hoverShows = [false, true].allSatisfy { dark in
                InkToken.controlHover.rgb(.silvanus, dark: dark) != InkToken.canvas.rgb(.silvanus, dark: dark)
                    && InkToken.controlHover.rgb(.reference, dark: dark) != InkToken.canvas.rgb(.reference, dark: dark)
            }
            check("controlHover differs from the canvas in both themes and sets", hoverShows)
            check("the kit's Silvanus colors come from the brand palette",
                  InkToken.missingFromBrand.isEmpty, InkToken.missingFromBrand.joined(separator: ", "))

            await checkWindowFrame(model: model)
            await checkHeaders(model: model)
            await checkSettings(model: model)
            await checkModels(model: model)
            await checkNotesAcrossViews(model: model)
            await checkTranscript(model: model)
            await checkPlayback()
            await checkSummary(model: model)
            await checkTodos(model: model)
            checkAudio()
            await checkMicRestarts()
            await checkMeetingDetection(model: model)
            await checkRecording(model: model)
            await checkCalendar(model: model)
            if ProcessInfo.processInfo.environment["APP_SELFTEST_AUDIO"] == "1" {
                await checkAfterCall(model: model)
                await checkRecordedSpeech(model: model)
            }

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    /// The window frame from design/KIT.md "Window": default and minimum sizes, the traffic
    /// lights' centers, and View > Hide Sidebar (⌃⌘S) hiding and showing the sidebar.
    private static func checkWindowFrame(model: AppModel) async {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            check("the main window is open", false)
            return
        }
        check("the window opens at 910 × 600", window.frame.size == Metric.windowDefault, "\(window.frame.size)")
        check("the window's minimum is 720 × 480", window.minSize == Metric.windowMinimum, "\(window.minSize)")
        let centers = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { type -> CGPoint? in
            guard let button = window.standardWindowButton(type), let container = button.superview else { return nil }
            let frame = container.convert(button.frame, to: nil)
            return CGPoint(x: frame.midX, y: window.frame.height - frame.midY)
        }
        let expected = (0..<3).map {
            CGPoint(x: Metric.trafficLightFirst.x + CGFloat($0) * Metric.trafficLightPitch, y: Metric.trafficLightFirst.y)
        }
        let placed = centers.count == 3 && zip(centers, expected).allSatisfy { abs($0.x - $1.x) <= 1 && abs($0.y - $1.y) <= 1 }
        check("the traffic lights sit within 1 pt of KIT.md's centers", placed, "\(centers)")

        // Double-clicking the header follows the Desktop & Dock setting, without changing it.
        let choices = [("Maximize", "zoom"), ("Minimize", "minimize"), ("None", "none"), (nil, "zoom")]
        let wrong = choices.compactMap { setting, expected -> String? in
            var called = "none"
            TitleBarDoubleClick.handle(setting: setting, zoom: { called = "zoom" }, minimize: { called = "minimize" })
            return called == expected ? nil : "\(setting ?? "unset") did \(called)"
        }
        check("double-clicking the header zooms, minimizes, or does nothing per the setting",
              wrong.isEmpty, wrong.joined(separator: ", "))

        // Header clicks reach the right view: the toggle button over the header's click
        // target, the click target in empty header space, and never the hidden sidebar's.
        let toggle = CGPoint(x: Metric.sidebarHeaderFirstX, y: Metric.trafficLightFirst.y)
        // Past the view pill and before the folder chip, in a 910 pt window.
        let emptyCanvasHeader = CGPoint(x: 480, y: Metric.trafficLightFirst.y)
        let onToggle = headerArea(at: toggle, in: window)
        check("a click on the sidebar toggle goes to the button, not the header",
              onToggle == "other", onToggle)
        // Past the filter button (it ends at x 192).
        let onSidebar = headerArea(at: CGPoint(x: 200, y: Metric.trafficLightFirst.y), in: window)
        check("a click in the empty sidebar header goes to the header", onSidebar == "sidebar", onSidebar)
        let onEmpty = headerArea(at: emptyCanvasHeader, in: window)
        check("a click in the empty canvas header goes to the header", onEmpty == "canvas", onEmpty)

        let item = menuItem(key: "s", modifiers: [.control, .command], in: NSApp.mainMenu)
        check("View has Hide Sidebar on ⌃⌘S", item?.title == "Hide Sidebar", item?.title ?? "missing")
        guard let item, let menu = item.menu else { return }
        menu.performActionForItem(at: menu.index(of: item))
        // Wait for the sidebar to hide and the header to settle, up to 2 s.
        await poll { !model.sidebarVisible && headerArea(at: CGPoint(x: 150, y: Metric.trafficLightFirst.y), in: window) == "canvas" }
        // Hidden, the sidebar's header takes nothing: under the toggle (x 100) the button
        // still wins, and where the sidebar's other buttons were (x 150, x 200) the canvas
        // header's empty space does (no meeting is open, so no view pill there).
        let hiddenToggle = headerArea(at: CGPoint(x: 100, y: Metric.trafficLightFirst.y), in: window)
        let hiddenPast = headerArea(at: CGPoint(x: 200, y: Metric.trafficLightFirst.y), in: window)
        check("with the sidebar hidden, header clicks go to the button or the canvas header",
              hiddenToggle == "other" && hiddenPast == "canvas", "x 100: \(hiddenToggle), x 200: \(hiddenPast)")
        // AppKit leaves the hidden sidebar's click view at its old 208 pt frame (the canvas
        // happens to sit over it today); asked directly, it must refuse every point.
        func clickViews(_ view: NSView) -> [HeaderClickView.ClickView] {
            ((view as? HeaderClickView.ClickView).map { [$0] } ?? []) + view.subviews.flatMap(clickViews)
        }
        let sidebarViews = window.contentView.map(clickViews)?.filter { $0.area == .sidebar } ?? []
        let claims = sidebarViews.filter { $0.hitTest(NSPoint(x: $0.frame.midX, y: $0.frame.midY)) != nil }
        check("with the sidebar hidden, its header refuses clicks", !sidebarViews.isEmpty && claims.isEmpty,
              "\(sidebarViews.count) views, \(claims.count) still take clicks")
        // SwiftUI refreshes menu titles when the menu is about to open.
        await poll {
            NSApp.mainMenu?.update()
            menu.delegate?.menuNeedsUpdate?(menu)
            return menuItem(key: "s", modifiers: [.control, .command], in: NSApp.mainMenu)?.title == "Show Sidebar"
        }
        let hidden = !model.sidebarVisible
        let showTitle = menuItem(key: "s", modifiers: [.control, .command], in: NSApp.mainMenu)?.title
        check("⌃⌘S hides the sidebar and the item turns to Show Sidebar", hidden && showTitle == "Show Sidebar",
              "visible \(model.sidebarVisible), title \(showTitle ?? "missing")")
        if let again = menuItem(key: "s", modifiers: [.control, .command], in: NSApp.mainMenu), let menu = again.menu {
            menu.performActionForItem(at: menu.index(of: again))
        }
        await poll { model.sidebarVisible }
        check("⌃⌘S again shows the sidebar", model.sidebarVisible)
    }

    /// Settings inside the window: ⌘, and the back button and Escape, the appearance choice
    /// (saved, and applied to every window), and the Show in Dock stub.
    private static func checkSettings(model: AppModel) async {
        let item = menuItem(key: ",", modifiers: [.command], in: NSApp.mainMenu)
        check("the app menu has Settings… on ⌘,", item?.title == "Settings…", item?.title ?? "missing")
        check("no separate Settings window scene is left",
              !NSApp.windows.contains { $0.identifier?.rawValue.contains("Settings") == true || $0.title == "Settings" })
        if let item, let menu = item.menu { menu.performActionForItem(at: menu.index(of: item)) }
        try? await Task.sleep(for: .seconds(0.4))
        check("Settings… opens Settings in the main window", model.settingsOpen)
        let close = menuItem(key: "[", modifiers: [.command], in: NSApp.mainMenu)
        check("View has Close Settings on ⌘[", close?.title == "Close Settings", close?.title ?? "missing")
        model.closeSettings()
        check("the back button closes Settings", !model.settingsOpen)
        model.openSettings(.appearance)
        check("openSettings picks the pane", model.settingsOpen && model.settingsPane == .appearance)

        let original = NSApp.appearance
        let realAppearance = UserDefaults.standard.string(forKey: AppDefaults.appearanceKey)
        model.appearance = .dark
        check("choosing Dark applies to the app and is saved",
              NSApp.appearance?.name == .darkAqua && AppDefaults.shared.string(forKey: AppDefaults.appearanceKey) == "dark")
        model.appearance = .light
        check("choosing Light applies to the app and is saved",
              NSApp.appearance?.name == .aqua && AppDefaults.appearance == .light)
        model.appearance = .system
        check("choosing System follows the Mac again", NSApp.appearance == nil && AppDefaults.appearance == .system)
        check("the real defaults are left alone by the appearance choice",
              UserDefaults.standard.string(forKey: AppDefaults.appearanceKey) == realAppearance)
        NSApp.appearance = original

        check("Show in Dock starts on", model.showInDock)
        model.showInDock = false
        check("Show in Dock is saved and nothing else changes yet",
              AppDefaults.shared.object(forKey: AppDefaults.showInDockKey) as? Bool == false)
        model.showInDock = true
        // Commands follow `settingsOpen`: Rename Meeting… is disabled behind Settings.
        if model.selectedMeeting == nil { model.newMeeting() }
        func renameEnabled() async -> Bool? {
            try? await Task.sleep(for: .seconds(0.3))
            NSApp.mainMenu?.update()
            let menu = NSApp.mainMenu?.items.first { $0.title == "Meeting" }?.submenu
            menu.map { $0.delegate?.menuNeedsUpdate?($0) }
            return menuItem(key: "r", modifiers: [.control, .command], in: NSApp.mainMenu)?.isEnabled
        }
        let hasMeeting = model.selectedMeeting != nil
        model.openSettings()
        let whileOpen = await renameEnabled()
        model.closeSettings()
        let afterClose = await renameEnabled()
        check("Rename Meeting… is disabled while Settings is open and enabled again after",
              hasMeeting && whileOpen == false && afterClose == true,
              "meeting \(hasMeeting), open \(String(describing: whileOpen)), closed \(String(describing: afterClose))")
        // Meeting commands never act behind Settings: New Meeting closes it first.
        model.openSettings()
        model.newMeeting()
        check("New Meeting closes Settings first", !model.settingsOpen)
        model.openSettings()
        model.show(.summary)
        check("a view mode closes Settings first", !model.settingsOpen && model.canvasMode == .summary)
        model.show(.notes)
        model.closeSettings()
        model.settingsPane = .general

        check("Settings has a Summaries pane under AI",
              SettingsPane.groups.last?.items.map(\.id) == [.transcription, .summaries])
    }

    /// The model that writes to-dos and summaries (S-042): the downloader against a tiny
    /// made-up file served from memory (never the network, never a real model), then the
    /// same through the app's state: which file is in use, Remove, and Home's card.
    private static func checkModels(model: AppModel) async {
        let models = model.summaryModels
        let files = FileManager.default
        check("test runs keep downloaded models in the scratch store",
              models.folder.path.hasPrefix(Store.root.path) && models.staged == nil, models.folder.path)
        check("the 12B model is recommended from 24 GB of memory, the small one below",
              LocalModelCatalog.recommended(physicalMemory: 32 << 30)?.id == "12b"
              && LocalModelCatalog.recommended(physicalMemory: 16 << 30)?.id == "small")

        // A 6 KB stand-in for a model, with its real checksum.
        let data = Data((0..<6_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 / 7) })
        let scratch = Store.root.appending(path: "download-check")
        try? files.createDirectory(at: scratch, withIntermediateDirectories: true)
        let reference = scratch.appending(path: "reference")
        try? data.write(to: reference)
        let sum = ModelDownloadRules.sha256(of: reference) ?? ""
        func stand(_ name: String, sha256: String? = nil) -> CatalogModel {
            CatalogModel(id: name, name: "Stand-in \(name)", url: URL(string: "https://example.invalid/\(name)/stand-in-\(name).gguf")!,
                         bytes: Int64(data.count), sha256: sha256 ?? sum, memoryGB: 1, bestFor: "For checks.")
        }
        func size(_ url: URL) -> Int { ((try? files.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? -1 }
        /// One run of the downloader into `folder`: the events, and the error if it threw.
        func run(_ item: CatalogModel, in folder: URL, transport: ModelTransport,
                 free: Int64? = nil) async -> (events: [ModelDownloader.Event], error: Error?) {
            let seen = EventLog()
            do {
                _ = try await ModelDownloader.download(item, into: folder, transport: transport,
                                                       freeSpace: { _ in free }, progressStep: 1_000) { seen.add($0) }
                return (seen.events, nil)
            } catch {
                return (seen.events, error)
            }
        }
        func bytes(_ events: [ModelDownloader.Event]) -> [Int64] {
            events.compactMap { if case let .progress(done) = $0 { done } else { nil } }
        }

        // Start to finish: progress climbs to the size, the file is checked, then it has its name.
        let whole = stand("whole")
        let wholeFolder = scratch.appending(path: "whole")
        let wholeLog = ModelTransport.FixtureLog()
        let first = await run(whole, in: wholeFolder, transport: .fixture(data, log: wholeLog))
        let steps = bytes(first.events)
        check("a download reports its progress up to the file's size",
              first.error == nil && steps.count >= 4 && steps == steps.sorted() && steps.last == Int64(data.count),
              "\(steps)")
        check("a download is checked after the last byte, then given its name",
              first.events.last == .checking
              && (try? Data(contentsOf: wholeFolder.appending(path: whole.fileName))) == data
              && !files.fileExists(atPath: wholeFolder.appending(path: whole.partialName).path)
              && wholeLog.offsets == [0])

        // The wrong checksum: the file is deleted and the failure says so.
        let wrong = stand("wrong", sha256: String(repeating: "0", count: 64))
        let wrongFolder = scratch.appending(path: "wrong")
        let bad = await run(wrong, in: wrongFolder, transport: .fixture(data))
        check("a file that fails its checksum is deleted and reported",
              (bad.error as? ModelDownloadError) == .failedCheck
              && ((try? files.contentsOfDirectory(atPath: wrongFolder.path)) ?? ["?"]).isEmpty,
              "\(String(describing: bad.error))")
        let long = Data(data + data)
        let tooMuch = await run(stand("long"), in: scratch.appending(path: "long"), transport: .fixture(long))
        check("a file that's the wrong size is deleted and reported",
              (tooMuch.error as? ModelDownloadError) == .failedCheck
              && ((try? files.contentsOfDirectory(atPath: scratch.appending(path: "long").path)) ?? ["?"]).isEmpty,
              "\(String(describing: tooMuch.error))")

        // A dropped connection keeps what arrived; the next try asks for the rest only.
        let cut = stand("cut")
        let cutFolder = scratch.appending(path: "cut")
        let dropped = await run(cut, in: cutFolder, transport: .fixture(data, piece: 500, stopAfter: 2_000))
        let kept = size(cutFolder.appending(path: cut.partialName))
        check("a dropped connection keeps the part that arrived",
              (dropped.error as? ModelDownloadError) == .interrupted && kept == 2_000
              && !files.fileExists(atPath: cutFolder.appending(path: cut.fileName).path),
              "kept \(kept), \(String(describing: dropped.error))")
        let resumeLog = ModelTransport.FixtureLog()
        let resumed = await run(cut, in: cutFolder, transport: .fixture(data, log: resumeLog))
        check("the next try resumes from the partial file and the whole file checks out",
              resumed.error == nil && resumeLog.offsets == [2_000] && bytes(resumed.events).first == 2_000
              && (try? Data(contentsOf: cutFolder.appending(path: cut.fileName))) == data,
              "asked from \(resumeLog.offsets), \(String(describing: resumed.error))")

        // Cancel stops it partway and keeps the part, with no file under the real name.
        let stopped = stand("stopped")
        let stoppedFolder = scratch.appending(path: "stopped")
        let stoppedPartial = stoppedFolder.appending(path: stopped.partialName)
        let slow = Task { await run(stopped, in: stoppedFolder, transport: .fixture(data, piece: 200, pause: .milliseconds(20))) }
        await poll { size(stoppedPartial) >= 400 }
        slow.cancel()
        let cancelled = await slow.value
        let partway = size(stoppedPartial)
        check("Cancel stops a download partway and keeps what arrived",
              cancelled.error is CancellationError && partway >= 400 && partway < data.count
              && !files.fileExists(atPath: stoppedFolder.appending(path: stopped.fileName).path),
              "\(partway) bytes, \(String(describing: cancelled.error))")

        // No room, and a server that says no: refused in plain words, nothing fetched.
        let roomLog = ModelTransport.FixtureLog()
        let full = await run(stand("full"), in: scratch.appending(path: "full"), transport: .fixture(data, log: roomLog), free: 1_000)
        check("a download is refused when the disk has no room",
              full.error?.localizedDescription.hasPrefix("Not enough disk space.") == true && roomLog.offsets.isEmpty,
              full.error?.localizedDescription ?? "no error")
        let missing = ModelTransport { _, _, head, _ in try head(.init(status: 404, contentRange: nil)) }
        let refused = await run(stand("refused"), in: scratch.appending(path: "refused"), transport: missing)
        check("a server that says no is reported", (refused.error as? ModelDownloadError) == .refused(404))

        // The same through the app: Download, the model in use, Remove, and Home's card.
        let savedCatalog = models.catalog
        let savedMemory = models.physicalMemory
        let savedConfirm = model.confirmRemoval
        defer {
            models.catalog = savedCatalog
            models.physicalMemory = savedMemory
            models.transport = .live
            model.confirmRemoval = savedConfirm
            model.summaryModelPath = nil
            model.modelSetupHidden = false
            try? files.removeItem(at: models.folder)
            try? files.removeItem(at: scratch)
        }
        let big = stand("big"), little = stand("little")
        models.catalog = [big, little]
        models.physicalMemory = 16 << 30
        models.progressStep = 1_000
        model.summaryModelPath = nil
        model.modelSetupHidden = false
        check("with no model, Home offers the one recommended for this Mac",
              model.summaryModel == nil && model.showsModelSetup && models.recommended?.id == "little"
              && models.state(of: little) == .notDownloaded)

        models.transport = .fixture(data, piece: 200, pause: .milliseconds(10))
        let work = models.download(little)
        await poll { if case let .downloading(done) = models.state(of: little) { done > 0 } else { false } }
        let midway = models.state(of: little)
        check("a download shows its progress, and Home keeps its card meanwhile",
              { if case let .downloading(done) = midway { done > 0 && done < Int64(data.count) } else { false } }()
              && model.showsModelSetup && models.isBusy, "\(midway)")
        await work?.value
        check("a downloaded model is in use, and Home's card is gone for good",
              models.state(of: little) == .downloaded && model.summaryModel?.source == .downloaded
              && model.summaryModel?.name == little.name && !model.showsModelSetup && model.modelSetupHidden && !models.isBusy,
              "\(models.state(of: little))")

        // With both downloaded the recommended one is used; a chosen file wins over both.
        models.transport = .fixture(data)
        await models.download(big)?.value
        check("with both downloaded, the recommended one is used", model.summaryModel?.name == little.name)
        models.physicalMemory = 32 << 30
        check("on a Mac with more memory the larger one is used", model.summaryModel?.name == big.name)
        let chosen = scratch.appending(path: "my-own.gguf")
        files.createFile(atPath: chosen.path, contents: Data())
        model.summaryModelPath = chosen.path
        check("a chosen model file is saved and used",
              AppDefaults.shared.string(forKey: AppDefaults.modelFileKey) == chosen.path
              && model.summaryModel?.url.path == chosen.path && model.summaryModel?.source == .chosen)
        model.summaryModelPath = nil
        check("Use Downloaded Model forgets the chosen file",
              AppDefaults.shared.string(forKey: AppDefaults.modelFileKey) == nil && model.summaryModel?.source == .downloaded)

        // Remove asks first, naming the size; Cancel there keeps the file.
        var asked: [String] = []
        model.confirmRemoval = { item, bytes in
            asked.append(AppModel.removeQuestion(item) + " " + AppModel.removeDetail(bytes: bytes))
            return false
        }
        model.removeSummaryModel(big)
        check("Remove asks first and names the size",
              asked == ["Remove Stand-in big? This deletes the 6 KB file from this Mac. To use the model again, you'd download it again."]
              && models.state(of: big) == .downloaded, asked.joined())
        check("the question for the 12B model names 7.4 GB", AppModel.removeDetail(bytes: LocalModelCatalog.large.bytes).contains("7.4 GB"))
        model.confirmRemoval = { _, _ in true }
        model.removeSummaryModel(big)
        model.removeSummaryModel(little)
        check("Remove deletes the model's file, and there's no model again",
              models.state(of: big) == .notDownloaded && model.summaryModel == nil
              && ((try? files.contentsOfDirectory(atPath: models.folder.path)) ?? []).isEmpty)
        check("Home's card stays away after a model was in place", !model.showsModelSetup)

        // A failure says why and Retry picks up; Cancel leaves a partial one to Resume.
        models.transport = .fixture(data, piece: 500, stopAfter: 1_500)
        await models.download(big)?.value
        check("a failed download says why in plain words",
              models.state(of: big) == .failed(ModelDownloadError.interrupted.localizedDescription), "\(models.state(of: big))")
        let retryLog = ModelTransport.FixtureLog()
        models.transport = .fixture(data, log: retryLog)
        await models.download(big)?.value
        check("Retry picks up where the download stopped", models.state(of: big) == .downloaded && retryLog.offsets == [1_500],
              "\(retryLog.offsets)")
        models.transport = .fixture(data, piece: 200, pause: .milliseconds(20))
        let pausing = models.download(little)
        await poll { size(models.folder.appending(path: little.partialName)) >= 400 }
        models.cancel(little)
        await pausing?.value
        check("Cancel leaves a partial download to resume",
              { if case let .partial(done) = models.state(of: little) { done >= 400 && done < Int64(data.count) } else { false } }(),
              "\(models.state(of: little))")
        try? files.removeItem(at: models.folder)
        models.remove(big)
        model.modelSetupHidden = false
        check("Not Now puts Home's card away", {
            guard model.showsModelSetup else { return false }
            model.modelSetupHidden = true
            return !model.showsModelSetup && AppDefaults.shared.bool(forKey: AppDefaults.modelSetupHiddenKey)
        }())
    }

    /// The headers (task 4): New Meeting, renaming and filing a meeting, the view menu's
    /// ⌘1 to ⌘3, and the canvas header's controls clear of the traffic lights and each other
    /// at the default and minimum sizes with a 120-character title (Review Focus 2).
    private static func checkHeaders(model: AppModel) async {
        let before = model.meetings.count
        let newItem = menuItem(key: "n", modifiers: [.command], in: NSApp.mainMenu)
        check("File has New Meeting on ⌘N", newItem?.title == "New Meeting", newItem?.title ?? "missing")
        if let newItem, let menu = newItem.menu { menu.performActionForItem(at: menu.index(of: newItem)) }
        try? await Task.sleep(for: .seconds(0.3))
        let created = model.selectedMeeting
        check("⌘N makes a meeting, saves it, opens it on My notes",
              model.meetings.count == before + 1 && created != nil && model.canvasMode == .notes
              && model.library.folderURL(for: created?.id ?? "") != nil,
              "count \(before) -> \(model.meetings.count), selected \(created?.id ?? "none")")
        check("a new meeting is saved as Untitled meeting, not an empty title",
              model.library.loadAll().meetings.first { $0.id == created?.id }?.info.title == Meeting.untitled)
        for (key, title) in [("r", "Start Recording"), ("n", "Quick Note")] {
            let modifiers: NSEvent.ModifierFlags = key == "r" ? [.shift, .command] : [.option, .command]
            let item = menuItem(key: key, modifiers: modifiers, in: NSApp.mainMenu)
            check("File has \(title), enabled",
                  item?.title == title && item?.isEnabled == true && model.canRecord, item?.title ?? "missing")
        }
        guard let id = created?.id else { return }
        model.rename(id, to: "   ")
        check("an empty title is ignored and nothing is written",
              model.selectedMeeting?.info.title == Meeting.untitled
              && model.library.loadAll().meetings.first { $0.id == id }?.info.title == Meeting.untitled)
        NSApp.mainMenu?.update()
        let meetingMenu = NSApp.mainMenu?.items.first { $0.title == "Meeting" }?.submenu
        meetingMenu.map { $0.delegate?.menuNeedsUpdate?($0) }
        try? await Task.sleep(for: .seconds(0.3))
        let rename = menuItem(key: "r", modifiers: [.control, .command], in: NSApp.mainMenu)
        let attendees = menuItem(key: "a", modifiers: [.control, .command], in: NSApp.mainMenu)
        let move = meetingMenu?.items.first { $0.title == "Move to Folder" }
        check("Meeting has Rename Meeting… (⌃⌘R), Show Attendees (⌃⌘A), and Move to Folder",
              rename?.title == "Rename Meeting…" && attendees?.title == "Show Attendees" && move?.hasSubmenu == true,
              "\(rename?.title ?? "missing"), \(attendees?.title ?? "missing"), \(move?.title ?? "missing")")
        // Each Meeting item works from Transcript, where the header isn't on screen yet: the
        // request waits for the header to mount, and the header acts on it.
        let mainWindow = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet })
        check("the main window is open for the Meeting menu checks", mainWindow != nil, "no main window")
        let newFolderItem = move?.submenu?.items.first { $0.title == "New Folder…" }
        let cases: [(HeaderRequest, String, NSMenuItem?)] = [
            (.rename, "Rename Meeting…", rename), (.attendees, "Show Attendees", attendees),
            (.newFolder, "Move to Folder > New Folder…", newFolderItem),
        ]
        for (kind, title, item) in cases {
            guard let main = mainWindow else { break }
            model.canvasMode = .transcript
            try? await Task.sleep(for: .seconds(0.4))
            let handledBefore = model.handledHeaderRequests.count
            if let item, let menu = item.menu { menu.performActionForItem(at: menu.index(of: item)) }
            try? await Task.sleep(for: .seconds(0.8))
            let consumed = model.headerRequest == nil && model.handledHeaderRequests.count == handledBefore + 1
                && model.handledHeaderRequests.last == kind && model.canvasMode == .notes
            let popovers = NSApp.windows.filter { $0.isVisible && $0.className.contains("Popover") }
            let acted = switch kind {
            case .rename: main.firstResponder is NSText
            case .attendees: !popovers.isEmpty
            case .newFolder: main.attachedSheet != nil || NSApp.windows.contains { $0.isVisible && $0 is NSPanel }
            }
            check("\(title) from Transcript opens My notes and the header acts on it", consumed && acted,
                  "consumed \(consumed), acted \(acted), mode \(model.canvasMode)")
            // Put things back: end the edit, close the popover and the prompt.
            main.makeFirstResponder(nil)
            popovers.forEach { $0.close() }
            if let sheet = main.attachedSheet { main.endSheet(sheet) }
            for panel in NSApp.windows where panel.isVisible && panel is NSPanel { panel.close() }
            try? await Task.sleep(for: .seconds(0.4))
        }
        // A request waiting for the header never carries over to another meeting.
        let second = Meeting(info: MeetingInfo(title: "Weekly sync", start: Date().addingTimeInterval(-3_600)))
        _ = try? model.library.save(second)
        model.meetings.append(second)
        let other = model.meetings.first { $0.id != model.selection }?.id
        model.requestRename()
        let pending = model.headerRequest
        model.selection = other
        check("changing the open meeting drops a waiting header request",
              other != nil && pending == .rename && model.headerRequest == nil,
              "other \(other ?? "none"), pending \(String(describing: pending)), now \(String(describing: model.headerRequest))")
        model.selection = id
        try? model.library.moveToTrash(second.id)
        model.meetings.removeAll { $0.id == second.id }
        model.show(.notes)
        try? await Task.sleep(for: .seconds(0.3))
        mainWindow?.makeFirstResponder(nil)

        // ⌘F stays Edit > Find for the notes canvas; the Search placeholder has no shortcut.
        let find = menuItem(key: "f", modifiers: [.command], in: NSApp.mainMenu)
        let search = meetingMenu?.items.first { $0.title == "Search" }
        let filter = meetingMenu?.items.first { $0.title == "Filter" }
        check("⌘F is Edit > Find, and Search and Filter claim no shortcut",
              find?.title.hasPrefix("Find") == true && search?.keyEquivalent == "" && filter?.keyEquivalent == "",
              "⌘F: \(find?.title ?? "missing"), Search \(search?.keyEquivalent ?? "missing"), Filter \(filter?.keyEquivalent ?? "missing")")

        model.rename(id, to: "  Acme   kickoff  ")
        let reread = model.library.loadAll().meetings.first { $0.id == id }
        check("renaming saves the tidy title and the sidebar shows it",
              reread?.info.title == "Acme kickoff" && model.selectedMeeting?.displayTitle == "Acme kickoff"
              && model.dayGroups.flatMap(\.meetings).contains { $0.id == id && $0.info.title == "Acme kickoff" },
              reread?.info.title ?? "not on disk")
        model.setFolder(id, to: "Clients")
        check("filing a meeting saves its folder and the sidebar lists it",
              model.library.loadAll().meetings.first { $0.id == id }?.info.folder == "Clients"
              && model.folders.map(\.name) == ["Clients"])

        // SwiftUI refreshes menu items (here, enabled now that a meeting is open) as a menu opens.
        NSApp.mainMenu?.update()
        if let view = menuItem(key: "1", modifiers: [.command], in: NSApp.mainMenu)?.menu {
            view.delegate?.menuNeedsUpdate?(view)
        }
        try? await Task.sleep(for: .seconds(0.3))
        for mode in CanvasMode.allCases {
            let item = menuItem(key: String(mode.shortcut), modifiers: [.command], in: NSApp.mainMenu)
            if let item, let menu = item.menu { menu.performActionForItem(at: menu.index(of: item)) }
            try? await Task.sleep(for: .seconds(0.2))
            check("View > \(mode.title) (⌘\(mode.shortcut)) shows it", item?.title == mode.title && model.canvasMode == mode,
                  "\(item?.title ?? "missing"), mode \(model.canvasMode)")
        }
        model.show(.notes)

        // Review Focus 2: the longest title and folder name at both sizes.
        model.rename(id, to: HeadersGallery.longTitle)
        model.setFolder(id, to: HeadersGallery.longFolder)
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            check("the main window is open for the header layout checks", false, "no main window")
            try? model.library.moveToTrash(id)
            model.reload()
            return
        }
        let names = ["hideSidebar", "search", "newMeeting", "filter",
                     "headerPill", "headerMic", "headerRecord", "headerMore"]
        // The traffic lights' right edge: the zoom button's center plus its 7 pt radius.
        let lightsEnd = Metric.trafficLightFirst.x + 2 * Metric.trafficLightPitch + 7
        for size in [Metric.windowDefault, Metric.windowMinimum] {
            window.setContentSize(size)
            try? await Task.sleep(for: .seconds(0.6))
            let probes = GridProbes.shared.probes.values
            let frames = names.compactMap { name in
                probes.first { $0.name == name }.map { (name, CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)) }
            }
            let ranges = frames.map { "\($0.0) \(fmt($0.1.minX))-\(fmt($0.1.maxX))" }.joined(separator: ", ")
            print("HEADER \(Int(size.width)) × \(Int(size.height)): \(ranges)")
            var overlaps: [String] = []
            for (index, first) in frames.enumerated() {
                for second in frames.dropFirst(index + 1) where first.1.intersection(second.1).width > 0.25 {
                    overlaps.append("\(first.0)/\(second.0)")
                }
            }
            let clear = frames.allSatisfy { $0.1.minX >= lightsEnd && $0.1.maxX <= size.width && $0.1.minY >= Metric.controlY - 0.5
                && $0.1.maxY <= Metric.controlY + Metric.controlHeight + 0.5 }
            check("at \(Int(size.width)) × \(Int(size.height)) the header controls clear the traffic lights and each other",
                  frames.count == names.count && overlaps.isEmpty && clear,
                  "\(frames.count) of \(names.count) found; overlaps \(overlaps); \(ranges)")
        }
        window.setContentSize(Metric.windowDefault)
        try? model.library.moveToTrash(id)
        model.reload()
        model.selection = nil
    }

    private static func fmt(_ value: CGFloat) -> String { String(format: "%g", value) }

    /// The color of a selected sidebar row's pill, away from its text, drawn on the sidebar.
    private static func selectionFill(appearsActive: Bool) -> String? {
        let row = Button {} label: { SidebarMeetingRow(title: "Acme kickoff", time: "9:30 AM") }
            .buttonStyle(SidebarRowStyle(isSelected: true))
            .frame(width: Metric.sidebarWidth)
            .background(Ink.sidebar)
            .environment(\.appearsActive, appearsActive)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: row)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let color = rep.colorAt(x: Int(Metric.sidebarWidth) - 12, y: Int(Metric.meetingRowPitch) / 2)?
                .usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255),
                      Int(color.blueComponent * 255))
    }

    /// My notes in the real window: the meeting header sits over the editor in one scroll
    /// view, and typing reaches the right meeting's notes.md when Settings opens, when the
    /// view mode changes (menu and view pill), across a rename, and before Move to Trash.
    /// ⌘⌫ while typing stays in the notes.
    private static func checkNotesAcrossViews(model: AppModel) async {
        guard let main = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            check("the main window is open", false)
            return
        }
        model.closeSettings()
        let earlier = main.contentView.flatMap(NotesTextView.find)
        guard let meeting = model.newMeeting() else {
            check("New Meeting saves a meeting for the notes checks", false)
            return
        }
        let id = meeting.id
        func editor() -> NotesTextView? { main.contentView.flatMap(NotesTextView.find) }
        func disk() -> String { model.library.readNotes(for: id) ?? "(no notes.md)" }
        /// Waits for My notes' editor, then types at the end of the note without waiting for a save.
        func type(_ text: String) async -> Bool {
            await poll { editor() != nil }
            guard let view = editor() else { return false }
            main.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            for c in text { view.insertText(String(c), replacementRange: view.selectedRange()) }
            return true
        }

        // The new meeting's editor, not the one it replaces.
        await poll { editor() != nil && editor() !== earlier }
        let header = editor()?.superview as? HeaderedNotesView
        check("My notes puts the meeting header above the notes in one scroll view",
              header != nil && header?.enclosingScrollView?.documentView === header
              && (header?.header.frame.maxY ?? 0) <= (header?.textView.frame.minY ?? 0) + (editor()?.textContainerInset.height ?? 0))
        check("VoiceOver reads the header, then the notes",
              header.map { ($0.accessibilityChildren() as? [NSView]) == [$0.header, $0.textView] } == true
              && editor()?.accessibilityLabel() == "My notes",
              "label \(editor()?.accessibilityLabel() ?? "none")")

        // Settings: the typing is on disk the moment it opens.
        let typed1 = await type("Budget")
        // Measured once there's a first line to measure.
        let line = editor()?.firstLineMetrics()
        check("the notes text starts at x 221, under the header",
              line.map { $0.x == Metric.contentX && abs($0.lineTop - (Metric.headerHeight + MeetingHeader.height)) <= 1 } == true,
              line.map { "x \($0.x), line top \($0.lineTop)" } ?? "no first line")
        model.openSettings()
        check("opening Settings saves the typing to the open meeting", typed1 && disk() == "Budget", disk().debugDescription)
        await poll { editor() == nil }
        check("Settings replaces the notes editor", editor() == nil)
        model.closeSettings()
        await poll { editor()?.string == "Budget" }
        check("closing Settings shows the same notes", editor()?.string == "Budget", editor()?.string.debugDescription ?? "no editor")

        // Tab from the header's controls lands in the notes.
        if let page = editor()?.superview as? HeaderedNotesView {
            // Key, but without activating the app: focus moves only in the key window.
            main.makeKey()
            main.makeFirstResponder(page.header)
            var path: [String] = []
            for _ in 0..<8 where !(main.firstResponder is NotesTextView) {
                if let tab = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                              windowNumber: main.windowNumber, context: nil, characters: "\t",
                                              charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48) {
                    main.sendEvent(tab)
                }
                try? await Task.sleep(for: .milliseconds(100))
                path.append((main.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? "none")
                            + (main.isKeyWindow ? "" : " (window not key)"))
            }
            // AppKit moves focus only in the key window, and an inactive app's window may not stay
            // key. Then check the step AppKit takes when Tab leaves the header's last control.
            if !main.isKeyWindow {
                main.makeFirstResponder(page.header)
                main.selectKeyView(following: page.header)
                path.append("key view after the header: \(main.firstResponder.map { String(describing: Swift.type(of: $0)) } ?? "none")")
            }
            check("Tab from the header moves into the notes",
                  main.firstResponder is NotesTextView,
                  path.joined(separator: " > "))
        } else {
            check("Tab from the header moves into the notes", false, "no header")
        }

        // View modes: ⌘1 (show) and the view pill (canvasMode).
        let typed2 = await type(" one")
        model.show(.summary)
        check("switching to Summary saves the typing", typed2 && disk() == "Budget one", disk().debugDescription)
        model.show(.notes)
        let typed3 = await type(" two")
        model.canvasMode = .transcript
        check("the view pill's Transcript saves the typing", typed3 && disk() == "Budget one two", disk().debugDescription)
        model.canvasMode = .notes

        // A rename after a save, and one with typing still unsaved, never rewrites notes.md.
        let typed4 = await type(" three")
        await poll(timeout: 4) { disk() == "Budget one two three" }
        let copy = model.meetings.first { $0.id == id }?.notes
        check("a notes save updates the app's copy of the meeting", typed4 && copy == "Budget one two three", copy.debugDescription)
        model.rename(id, to: "Acme review")
        check("a rename after a notes save leaves notes.md with the typed text",
              disk() == "Budget one two three" && model.meetings.first { $0.id == id }?.displayTitle == "Acme review",
              disk().debugDescription)
        let typed5 = await type(" four")
        model.rename(id, to: "Acme planning")
        check("a rename with typing unsaved doesn't write the older notes", disk() == "Budget one two three", disk().debugDescription)
        await poll(timeout: 4) { disk() == "Budget one two three four" }
        check("and the typing still saves after the rename", typed5 && disk() == "Budget one two three four", disk().debugDescription)
        model.setFolder(id, to: "Clients")
        check("a folder change leaves notes.md alone", disk() == "Budget one two three four", disk().debugDescription)

        // ⌘⌫ while typing deletes in the notes and never trashes the meeting.
        let trashItem = menuItem(title: "Move to Trash", in: NSApp.mainMenu)
        check("Meeting has Move to Trash on ⌘⌫",
              trashItem?.keyEquivalentModifierMask == [.command] && ["\u{8}", "\u{7F}"].contains(trashItem?.keyEquivalent ?? ""),
              "\(trashItem?.keyEquivalent.debugDescription ?? "missing") \(trashItem?.keyEquivalentModifierMask.rawValue ?? 0)")
        if await type(" five"), let view = editor(),
           let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
                                        windowNumber: main.windowNumber, context: nil, characters: "\u{7F}",
                                        charactersIgnoringModifiers: "\u{7F}", isARepeat: false, keyCode: 51) {
            let handled = main.performKeyEquivalent(with: event)
            check("⌘⌫ in the notes deletes to the line's start and keeps the meeting",
                  handled && view.string.isEmpty && model.meetings.contains { $0.id == id },
                  "handled \(handled), text \(view.string.debugDescription)")
        } else {
            check("⌘⌫ in the notes deletes to the line's start and keeps the meeting", false, "no editor")
        }

        // ⌘⌫ while renaming deletes in the title's field and never trashes.
        let deleteKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
                                         windowNumber: main.windowNumber, context: nil, characters: "\u{7F}",
                                         charactersIgnoringModifiers: "\u{7F}", isARepeat: false, keyCode: 51)
        let returnKey = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: main.windowNumber, context: nil, characters: "\r",
                                         charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)
        check("only a ⌘⌫ key press counts as the delete shortcut",
              MoveToTrash.isDeleteShortcut(deleteKey) && !MoveToTrash.isDeleteShortcut(returnKey)
              && !MoveToTrash.isDeleteShortcut(nil))
        let requestsBefore = model.trashRequests.count
        model.requestRename()
        await poll { (main.firstResponder as? NSTextView).map { !($0 is NotesTextView) } == true }
        let field = main.firstResponder as? NSTextView
        let titleBefore = field?.string ?? ""
        MoveToTrash.perform(model: model, event: deleteKey, responder: main.firstResponder)
        check("⌘⌫ while renaming deletes in the title and never trashes",
              field != nil && !(field is NotesTextView) && !titleBefore.isEmpty && field?.string.isEmpty == true
              && model.trashRequests.count == requestsBefore && model.meetings.contains { $0.id == id },
              "field \(field.map { String(describing: Swift.type(of: $0)) } ?? "none"), title \(titleBefore.debugDescription) > \(field?.string.debugDescription ?? "")")
        main.makeFirstResponder(nil)
        try? await Task.sleep(for: .seconds(0.3))

        // Move to Trash with typing unsaved: saved first, so nothing is left to recover.
        let recovered = Store.root.appending(path: "recovered")
        let recoveredBefore = (try? FileManager.default.contentsOfDirectory(atPath: recovered.path))?.count ?? 0
        let typed6 = await type("Last line")
        if let trashItem, let menu = trashItem.menu {
            main.makeFirstResponder(nil)
            NSApp.mainMenu?.update()
            menu.delegate?.menuNeedsUpdate?(menu)
            menu.performActionForItem(at: menu.index(of: trashItem))
        }
        await poll { !model.meetings.contains { $0.id == id } }
        try? await Task.sleep(for: .seconds(0.3))
        let recoveredAfter = (try? FileManager.default.contentsOfDirectory(atPath: recovered.path))?.count ?? 0
        check("Move to Trash from the menu goes through AppModel.trash", model.trashRequests.last == id)
        check("Move to Trash saves the typing first and trashes the open meeting",
              typed6 && !model.meetings.contains { $0.id == id } && model.selection == nil && recoveredAfter == recoveredBefore,
              "listed \(model.meetings.contains { $0.id == id }), recovered \(recoveredAfter - recoveredBefore)")

        // The sidebar row's menu: Move to Trash goes through AppModel.trash too.
        await checkSidebarTrash(model: model, window: main)
    }

    /// Right-clicks the top sidebar row (a new meeting, so it's first under Today) and picks
    /// Move to Trash from the menu SwiftUI gives that spot.
    private static func checkSidebarTrash(model: AppModel, window: NSWindow) async {
        guard let meeting = model.newMeeting(), let content = window.contentView else {
            check("the sidebar row's Move to Trash goes through AppModel.trash", false, "no meeting")
            return
        }
        model.selection = nil
        try? await Task.sleep(for: .seconds(0.5))
        guard let row = model.sidebarOrder.firstIndex(of: meeting.id), row == 0 else {
            check("the sidebar row's Move to Trash goes through AppModel.trash", false, "row \(String(describing: model.sidebarOrder.firstIndex(of: meeting.id)))")
            return
        }
        // The first row under Today, in window points from the top left.
        var menu: NSMenu?
        var tried: [String] = []
        for y in stride(from: 110.0, through: 170.0, by: 10.0) where menu == nil {
            let point = NSPoint(x: 100, y: window.frame.height - y)
            guard let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                 clickCount: 1, pressure: 1),
                  let hit = content.superview?.hitTest(content.superview!.convert(point, from: nil)) else { continue }
            var view: NSView? = hit
            while let v = view, menu == nil {
                menu = v.menu(for: event)
                view = v.superview
            }
            tried.append("\(Int(y)): \(String(describing: type(of: hit)))")
        }
        let item = menu?.items.first { $0.title == "Move to Trash" }
        if let menu, let item { menu.performActionForItem(at: menu.index(of: item)) }
        await poll { !model.meetings.contains { $0.id == meeting.id } }
        check("the sidebar row's Move to Trash goes through AppModel.trash",
              item != nil && model.trashRequests.last == meeting.id && !model.meetings.contains { $0.id == meeting.id },
              "menu \(menu?.items.map(\.title) ?? []), tried \(tried.joined(separator: ", "))")
    }

    /// The Transcript view's data: transcript.json read back through the library, and one
    /// block per turn with the default speaker names. What ⌘3 draws, and a click on a word,
    /// are checked by the snapshot run (tools/snap.sh, "transcript").
    private static func checkTranscript(model: AppModel) async {
        let recorded = Meeting(info: MeetingInfo(id: "selftest-recorded", title: "Acme kickoff", start: Date(timeIntervalSince1970: 1_793_975_400)))
        let plain = Meeting(info: MeetingInfo(id: "selftest-plain", title: "Weekly sync", start: Date(timeIntervalSince1970: 1_793_971_800)))
        _ = try? model.library.save(recorded)
        _ = try? model.library.save(plain)
        try? model.library.saveTranscript(SeedData.kickoffTranscript, for: recorded.id)
        model.reload()
        let read = model.library.readTranscript(id: recorded.id)
        check("transcript.json reads back as it was written", read == SeedData.kickoffTranscript)
        check("a meeting without transcript.json has no transcript", model.library.readTranscript(id: plain.id) == nil)
        let names = SpeakerNames.resolve(info: recorded.info, defaultMe: AppDefaults.meName)
        let layout = read.map { TranscriptView.Layout($0, me: names.me, them: names.them) }
        check("the transcript groups into turns named Me and Them",
              layout?.blocks.first?.speaker == "Me" && layout?.blocks.dropFirst().first?.speaker == "Them"
              && zip(layout?.blocks ?? [], (layout?.blocks ?? []).dropFirst()).allSatisfy { $0.side != $1.side },
              layout?.blocks.map(\.speaker).joined(separator: ", ") ?? "none")
        check("low-confidence words are found", (layout?.words.filter(TranscriptLayout.isLowConfidence).count ?? 0) == 6)

        try? model.library.moveToTrash(recorded.id)
        try? model.library.moveToTrash(plain.id)
        model.reload()
    }

    /// Playback of two short `say` tracks in a /tmp meeting: both tracks load, a seek lands
    /// where it was asked, the highlighted word follows the engine's player time, pause holds
    /// still, and the end stops it. Muted, and about four seconds.
    private static func checkPlayback() async {
        let dir = Store.root.appending(path: "playback-\(UUID().uuidString.prefix(6))")
        let audio = dir.appending(path: MeetingFolder.audio)
        try? FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func speech(_ text: String, _ name: String) {
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-o", audio.appending(path: "\(name).caf").path, "--data-format=LEF32@16000", text]
            try? say.run()
            say.waitUntilExit()
        }
        speech("Thanks everyone, I will send the revised plan tomorrow morning, and then we can all go home.", "mic")
        speech("Priya will share the launch checklist before the next meeting.", "system")
        let player = MeetingPlayer()
        player.volume = 0
        check("two tracks load for playback", player.load(audio: audio) && player.duration > 2, "duration \(player.duration)")
        let none = MeetingPlayer()
        check("a meeting folder with no tracks has no audio", !none.load(audio: dir) && !none.hasAudio)

        // Words every half second over the audio's length, so a time maps to a known word.
        let words = (0..<Int(player.duration * 2)).map {
            Word(text: "w\($0)", start: Double($0) * 0.5, end: Double($0) * 0.5 + 0.4)
        }
        player.play(from: 1)
        let first = TranscriptLayout.wordIndex(at: player.currentTime, in: words)
        try? await Task.sleep(for: .seconds(1.2))
        let t1 = player.currentTime
        let followed = TranscriptLayout.wordIndex(at: t1, in: words)
        check("playing moves with the engine's player time, from where it was asked",
              player.isPlaying && t1 > 1.8 && t1 < 2.8, "time \(t1)")
        check("the highlighted word follows playback", (followed ?? 0) > (first ?? 0) && followed == Int(t1 / 0.5),
              "word \(first ?? -1) then \(followed ?? -1) at \(t1)")

        player.seek(to: 0.5)
        try? await Task.sleep(for: .milliseconds(300))
        let t2 = player.currentTime
        check("a seek while playing reschedules from the target", player.isPlaying && t2 >= 0.5 && t2 < 1.3, "time \(t2)")
        player.pause()
        let held = player.currentTime
        try? await Task.sleep(for: .milliseconds(300))
        check("pause holds the position", !player.isPlaying && player.currentTime == held && held >= 0.5, "time \(held)")
        player.seek(to: 1.5)
        check("a seek while paused only moves", !player.isPlaying && player.currentTime == 1.5)
        player.resume()
        try? await Task.sleep(for: .milliseconds(300))
        check("resume plays from the moved position", player.isPlaying && player.currentTime >= 1.5 && player.currentTime < 2.3,
              "time \(player.currentTime)")

        player.play(from: player.duration - 0.3)
        await poll(timeout: 2) { _ = player.currentTime; return !player.isPlaying }
        check("reaching the end stops playback at the end", !player.isPlaying && player.currentTime == player.duration,
              "time \(player.currentTime) of \(player.duration)")
        player.stop()
    }

    /// To-dos (S-041): the model's answer becomes todo.md, the Summary page shows it under
    /// a locked To-dos heading and above the locked summary, a tick is saved, and writing
    /// the list again keeps the tick and adds only what's new. The model is a stand-in:
    /// no check loads the real one.
    private static func checkTodos(model: AppModel) async {
        guard let main = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            check("the main window is open for the to-do checks", false)
            return
        }
        let summary = "## Overview\nAgreed on **scope**.\n"
        let meeting = Meeting(info: MeetingInfo(id: "selftest-todos", title: "Acme kickoff", start: Date(timeIntervalSince1970: 1_793_975_400)),
                              summary: summary, transcriptMarkdown: "[00:01] **Sam Rivera:** I'll send the project plan by Friday.")
        _ = try? model.library.save(meeting)
        model.reload()
        var answers = ["Sure:\n- [ ] Sam Rivera: send the project plan by Friday\n- [ ] Priya Shah: book the review room\n"]
        var requests: [String] = []
        model.todoModelIsInjected = true
        model.askModel = { _, user in
            requests.append(user)
            return answers.isEmpty ? "NONE" : answers.removeFirst()
        }
        defer {
            model.todoModelIsInjected = false
            model.askModel = { _, _ in throw LocalModelError.noModel }
        }
        check("Write To-dos is offered for a meeting with a transcript", model.canWriteTodos(meeting.id))
        await model.writeTodos(for: meeting.id, asked: true)?.value
        let first = "- [ ] Sam Rivera: send the project plan by Friday\n- [ ] Priya Shah: book the review room\n"
        check("the model's to-dos are written to todo.md", model.library.readTodo(id: meeting.id) == first,
              model.library.readTodo(id: meeting.id) ?? "none")
        check("the model is given the transcript", requests.first?.contains("I'll send the project plan by Friday.") == true)

        func editor() -> NotesTextView? { main.contentView.flatMap(NotesTextView.find) }
        model.closeSettings()
        model.sidebar = .all
        model.selection = meeting.id
        model.canvasMode = .summary
        let page = TodoPage(summary: summary).text(todo: first)
        await poll { editor()?.string == page }
        let view = editor()
        check("Summary shows To-dos, the list, then the summary", view?.string == page, view?.string.debugDescription ?? "no editor")
        if let view {
            main.makeFirstResponder(view)
            let summaryStart = (view.string as NSString).range(of: "## Overview").location
            view.setSelectedRange(NSRange(location: summaryStart + 3, length: 0))
            view.insertText("typed", replacementRange: view.selectedRange())
            view.setSelectedRange(NSRange(location: 2, length: 0))
            view.insertText("typed", replacementRange: view.selectedRange())
            check("the heading and the summary can't be changed", view.string == page, view.string.debugDescription)
            let box = (view.string as NSString).range(of: "[ ]").location
            check("a to-do's box can be ticked in place", view.toggleTask(at: box))
        }
        let ticked = first.replacingOccurrences(of: "- [ ] Sam", with: "- [x] Sam")
        await poll(timeout: 3) { model.library.readTodo(id: meeting.id) == ticked }
        check("the tick is saved to todo.md", model.library.readTodo(id: meeting.id) == ticked,
              model.library.readTodo(id: meeting.id) ?? "none")
        check("the Summary page with to-dos never writes summary.md", model.library.readSummary(id: meeting.id) == summary)

        answers = ["- [ ] Sam Rivera: send the project plan by Friday\n- [ ] Jordan Lee: share the deck\n"]
        await model.writeTodos(for: meeting.id, asked: true)?.value
        let merged = ticked + "- [ ] Jordan Lee: share the deck\n"
        check("writing the list again keeps my tick and adds only the new to-do",
              model.library.readTodo(id: meeting.id) == merged, model.library.readTodo(id: meeting.id) ?? "none")
        await poll { editor()?.string == TodoPage(summary: summary).text(todo: merged) }
        check("the open page shows the new list", editor()?.string == TodoPage(summary: summary).text(todo: merged))

        let quiet = Meeting(info: MeetingInfo(id: "selftest-no-todos", title: "Weekly sync", start: Date(timeIntervalSince1970: 1_793_971_800)),
                            transcriptMarkdown: "[00:01] **Sam Rivera:** Nothing new this week.")
        _ = try? model.library.save(quiet)
        model.reload()
        await model.writeTodos(for: quiet.id, asked: true)?.value
        check("a call with no to-dos says so", model.library.readTodo(id: quiet.id) == Todos.none + "\n")
        model.askModel = { _, _ in throw LocalModelError.noModel }
        await model.writeTodos(for: quiet.id, asked: true)?.value
        check("a missing model is reported, and the list is left alone",
              model.todoStatus[quiet.id] == .failed(LocalModelError.noModel.localizedDescription)
              && model.library.readTodo(id: quiet.id) == Todos.none + "\n")
        // The To-dos page: every meeting's open to-dos, ticked in place.
        let board = TodoBoard.groups(model.meetings).first { $0.meetingID == meeting.id }
        check("the To-dos page groups a meeting's to-dos under it", board?.items.map(\.done) == [true, false, false],
              "\(board?.items.map(\.text) ?? [])")
        let openBefore = model.openTodoCount
        model.showTodos()
        check("To-dos takes the canvas and keeps the meeting selected", model.showingTodos && model.selection == meeting.id)
        if let item = board?.items.last {
            model.toggleTodo(item)
            check("ticking on the To-dos page writes the meeting's todo.md",
                  model.library.readTodo(id: meeting.id) == ticked + "- [x] Jordan Lee: share the deck\n",
                  model.library.readTodo(id: meeting.id) ?? "none")
            check("the sidebar's count goes down by one", model.openTodoCount == openBefore - 1, "\(openBefore) -> \(model.openTodoCount)")
            model.toggleTodo(item)
            check("unticking puts it back", model.library.readTodo(id: meeting.id) == merged && model.openTodoCount == openBefore)
        }
        // Creating, rewording, and deleting from the To-dos page, in a meeting's list and in mine.
        if let item = board?.items.last {
            model.editTodo(item, text: "Jordan Lee: share the final deck")
            check("rewording on the To-dos page writes the meeting's todo.md",
                  model.library.readTodo(id: meeting.id) == ticked + "- [ ] Jordan Lee: share the final deck\n",
                  model.library.readTodo(id: meeting.id) ?? "none")
            model.addTodo("Order lunch", to: meeting.id)
            let withLunch = ticked + "- [ ] Jordan Lee: share the final deck\n- [ ] Order lunch\n"
            check("a to-do added on the To-dos page joins the meeting's list", model.library.readTodo(id: meeting.id) == withLunch)
            await poll { editor()?.string == TodoPage(summary: summary).text(todo: withLunch) }
            if let added = TodoBoard.items(in: withLunch, meetingID: meeting.id).last {
                model.deleteTodo(added)
                // The row as it is now: its words changed above.
                let reworded = TodoBoard.Item(meetingID: item.meetingID, line: item.line, text: "Jordan Lee: share the final deck", done: false)
                model.editTodo(reworded, text: "Jordan Lee: share the deck")
            }
            check("deleting and rewording back restore the list", model.library.readTodo(id: meeting.id) == merged,
                  model.library.readTodo(id: meeting.id) ?? "none")
        }
        let countBefore = model.openTodoCount
        model.addTodo("Renew the domain", to: TodoBoard.own)
        check("a to-do of my own is saved in the library's root, outside any meeting",
              model.library.readOwnTodo() == "- [ ] Renew the domain\n" && model.ownTodo == "- [ ] Renew the domain\n"
              && model.openTodoCount == countBefore + 1)
        if let mine = TodoBoard.items(in: model.ownTodo, meetingID: TodoBoard.own).first {
            model.toggleTodo(mine)
            check("my own to-do can be ticked", model.library.readOwnTodo() == "- [x] Renew the domain\n" && model.openTodoCount == countBefore)
            model.editTodo(TodoBoard.items(in: model.ownTodo, meetingID: TodoBoard.own)[0], text: "")
            check("clearing a to-do's words deletes it", model.library.readOwnTodo().isEmpty && model.ownTodo.isEmpty)
        }
        // Meeting > New To-do starts a list on a meeting that has none.
        let fresh = Meeting(info: MeetingInfo(id: "selftest-new-todo", title: "Design review", start: Date(timeIntervalSince1970: 1_793_964_600)))
        _ = try? model.library.save(fresh)
        model.reload()
        model.newTodo(in: fresh.id)
        check("New To-do starts the meeting's list and opens its Summary",
              model.library.readTodo(id: fresh.id) == "- [ ] New to-do\n" && model.selection == fresh.id
              && model.canvasMode == .summary && !model.showingTodos)
        await poll { editor()?.string == "## To-dos\n- [ ] New to-do" && editor()?.selectedRange().length == 9 }
        let selected = editor().map { ($0.string as NSString).substring(with: $0.selectedRange()) }
        check("the new to-do's words are selected, ready to type over", selected == AppModel.newTodoText, selected ?? "no editor")
        model.deleteTodo(TodoBoard.Item(meetingID: fresh.id, line: 0, text: AppModel.newTodoText, done: false))
        model.selection = meeting.id
        model.showTodos()

        model.open(meeting.id)
        check("opening a meeting leaves the To-dos page", !model.showingTodos)
        model.showTodos()
        model.openSettings()
        model.closeSettings()
        check("Settings comes back to the To-dos page", model.showingTodos)
        model.showingTodos = false

        // Write Summary (the local model's stand-in): a first summary, then one over an imported summary.
        model.askModel = { system, _ in
            system == Summaries.system ? "Here you go:\n## Overview\nNothing new this week.\n" : "NONE"
        }
        check("Write Summary is offered for a meeting with a transcript", model.canWriteSummary(quiet.id))
        await model.writeSummary(for: quiet.id, asked: true)?.value
        check("the model's summary is written to summary.md", model.library.readSummary(id: quiet.id) == "## Overview\nNothing new this week.\n",
              model.library.readSummary(id: quiet.id) ?? "none")
        await model.writeSummary(for: meeting.id, asked: true)?.value
        check("a summary that was already there is kept under the new one",
              model.library.readSummary(id: meeting.id) == "## Overview\nNothing new this week.\n\n" + summary,
              model.library.readSummary(id: meeting.id) ?? "none")
        await model.writeSummary(for: meeting.id, asked: true)?.value
        check("writing the summary again replaces only the model's part",
              model.library.readSummary(id: meeting.id) == "## Overview\nNothing new this week.\n\n" + summary)
        model.askModel = { _, _ in "I can't do that." }
        await model.writeSummary(for: quiet.id, asked: true)?.value
        check("an answer with no summary is reported and changes nothing",
              model.summaryStatus[quiet.id] != nil && model.library.readSummary(id: quiet.id) == "## Overview\nNothing new this week.\n")
        model.showHome()
        check("Home closes the open meeting and To-dos", model.isHome && model.selection == nil && !model.showingTodos)
        model.selection = meeting.id

        let bare = Meeting(info: MeetingInfo(id: "selftest-no-transcript", title: "Notes only", start: Date(timeIntervalSince1970: 1_793_968_200)))
        _ = try? model.library.save(bare)
        model.reload()
        check("Write To-dos and Write Summary are off without a transcript", !model.canWriteTodos(bare.id) && !model.canWriteSummary(bare.id))
        model.canvasMode = .notes
    }

    /// The Summary page: summary.md read back through the library, shown read-only in the
    /// notes' styling under the meeting header, and never written (bytes and modification
    /// time stay as they were after selecting, copying, and an attempt to type). Then the
    /// open time of a 2,000-line summary. The look is checked by the snapshot run ("summary").
    private static func checkSummary(model: AppModel) async {
        guard let main = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            check("the main window is open for the Summary checks", false)
            return
        }
        let text = "## Overview\nAgreed on **scope**.\n\n## Imported summary\n\n- one\n- two\n"
        let withSummary = Meeting(info: MeetingInfo(id: "selftest-summary", title: "Acme kickoff", start: Date(timeIntervalSince1970: 1_793_975_400)), summary: text)
        let without = Meeting(info: MeetingInfo(id: "selftest-no-summary", title: "Weekly sync", start: Date(timeIntervalSince1970: 1_793_971_800)))
        _ = try? model.library.save(withSummary)
        _ = try? model.library.save(without)
        model.reload()
        check("summary.md reads back through the library", model.library.readSummary(id: withSummary.id) == text)
        check("a meeting without a summary reads none", (model.library.readSummary(id: without.id) ?? "").isEmpty)

        let url = model.library.notesURL(for: withSummary.id)?.deletingLastPathComponent().appending(path: MeetingFolder.summary)
        func stamp() -> (Data?, Date?) {
            guard let url else { return (nil, nil) }
            return (try? Data(contentsOf: url), (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date)
        }
        let before = stamp()
        func editor() -> NotesTextView? { main.contentView.flatMap(NotesTextView.find) }
        model.closeSettings()
        model.sidebar = .all
        model.selection = withSummary.id
        // Set directly: show() animates, and an animated removal can wait on a display link.
        model.canvasMode = .summary
        await poll { editor()?.string == text }
        let view = editor()
        check("Summary shows summary.md in the notes' Markdown view", view?.string == text, view?.string.debugDescription ?? "no editor")
        check("the Summary text is read-only, selectable, and findable",
              view.map { !$0.isEditable && $0.isSelectable && $0.usesFindBar } == true)
        let page = view?.superview as? HeaderedNotesView
        check("Summary puts the meeting header above the text in one scroll view",
              page != nil && page?.enclosingScrollView?.documentView === page
              && (page?.header.frame.maxY ?? 0) <= (page?.textView.frame.minY ?? 0) + (view?.textContainerInset.height ?? 0))
        check("VoiceOver calls the Summary text Summary", view?.accessibilityLabel() == "Summary", view?.accessibilityLabel() ?? "none")
        if let view {
            main.makeFirstResponder(view)
            view.selectAll(nil)
            view.insertText("typed", replacementRange: view.selectedRange())
            view.deleteBackward(nil)
            _ = view.toggleTask(at: 0)
        }
        check("typing into Summary changes nothing", editor()?.string == text, editor()?.string.debugDescription ?? "no editor")
        try? await Task.sleep(for: .seconds(1.6))
        let after = stamp()
        check("the Summary page never writes summary.md",
              before.0 != nil && before.0 == after.0 && before.1 == after.1,
              "modified \(String(describing: before.1)) -> \(String(describing: after.1))")
        check("the Summary page never writes notes.md", (model.library.readNotes(for: withSummary.id) ?? "").isEmpty)

        model.selection = without.id
        await poll { editor() == nil }
        check("a meeting with no summary shows the empty state, not an editor", editor() == nil)

        // Open time: read, style, lay out, and draw 2,000 lines in an off-screen window.
        let long = (0..<2_000).map { line in
            switch line % 10 {
            case 0: "## Section \(line / 10)"
            case 1, 5: "- A **decision** about the `staging` plan, line \(line), with _some_ words to wrap across the page when it runs long enough to need a second line."
            default: "Line \(line) of the summary: Priya owns the plan and Sam shares the checklist by Friday."
            }
        }.joined(separator: "\n") + "\n"
        let big = Meeting(info: MeetingInfo(id: "selftest-long-summary", title: "Acme planning day", start: Date()), summary: long)
        _ = try? model.library.save(big)
        let size = CGSize(width: Metric.windowDefault.width - Metric.canvasX, height: Metric.windowDefault.height - Metric.headerHeight)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -6000, y: -6000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        let clock = ContinuousClock()
        let open = clock.measure {
            let read = MeetingLibrary(root: Store.root).readSummary(id: big.id) ?? ""
            let host = NSHostingView(rootView: MarkdownEditor(text: .constant(read), readOnly: true).background(Ink.canvas))
            host.frame = NSRect(origin: .zero, size: size)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            host.display()
        }
        let ms = Double(open.components.attoseconds) / 1e15 + Double(open.components.seconds) * 1000
        window.close()
        print(String(format: "SUMMARY open 2,000 lines: %.1f ms", ms))
        check("a 2,000-line summary opens in under 100 ms", ms < 100, String(format: "%.1f ms", ms))

        model.selection = nil
        model.canvasMode = .notes
        for meeting in [withSummary, without, big] { try? model.library.moveToTrash(meeting.id) }
        model.reload()
    }

    /// Segment files, stitching, and tracks.json from synthetic buffers. Opens no device.
    private static func checkAudio() {
        let dir = Store.root.appending(path: "audio-selftest")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // 65 seconds at 48 kHz stereo, in 1-second buffers, the way a device might deliver it.
        let device = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let writer = SegmentWriter(directory: dir, name: "system", recordingStart: .now)
        if let second = AVAudioPCMBuffer(pcmFormat: device, frameCapacity: 48_000) {
            second.frameLength = 48_000
            for _ in 0..<65 { writer.append(second) }
        }
        writer.finish()
        let segments = writer.segmentURLs.compactMap { try? AVAudioFile(forReading: $0) }
        check("a 65-second track rolls into three 30-second segment files",
              writer.segmentURLs.map(\.lastPathComponent) == ["system-0001.caf", "system-0002.caf", "system-0003.caf"],
              writer.segmentURLs.map(\.lastPathComponent).joined(separator: ", "))
        check("segments are stored as 16 kHz mono float",
              segments.count == 3 && segments.allSatisfy {
                  $0.fileFormat.sampleRate == 16_000 && $0.fileFormat.channelCount == 1
                      && $0.processingFormat.commonFormat == .pcmFormatFloat32
              })
        let total = segments.reduce(0) { $0 + $1.length }
        check("converting keeps the track's length", abs(total - 65 * 16_000) < 1_600, "got \(total) frames")

        // Three 1-second buffers already at 16 kHz make one segment; stitching adds 2 s in front.
        let mic = SegmentWriter(directory: dir, name: "mic", recordingStart: .now)
        if let tone = AVAudioPCMBuffer(pcmFormat: TrackFormat.format, frameCapacity: 16_000) {
            tone.frameLength = 16_000
            for _ in 0..<3 { mic.append(tone) }
        }
        mic.finish()
        check("the mic track is written as segment files", mic.segmentURLs.count == 1)
        let stitched = dir.appending(path: "mic.caf")
        try? Stitcher.stitch(mic.segmentURLs, leadingSilence: 2, to: stitched)
        let length = (try? AVAudioFile(forReading: stitched).length) ?? 0
        check("stitching adds the leading silence", length == 5 * 16_000, "got \(length) frames")

        let tracks = Tracks(mic: Tracks.Track(mic), system: Tracks.Track(startOffset: 1.5, seconds: 65))
        try? tracks.save(in: dir)
        check("tracks.json reads back as it was written", Tracks.load(from: dir) == tracks)
        check("the mic track's length is recorded", abs((tracks.mic?.seconds ?? 0) - 3) < 0.01)

        // A stereo device with the voice on one side is mixed down, not cut to its first channel.
        let stereo = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let mixed = SegmentWriter(directory: dir, name: "mixed", recordingStart: .now)
        if let left = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 48_000) {
            left.frameLength = 48_000
            for i in 0..<48_000 { left.floatChannelData![0][i] = 0.8; left.floatChannelData![1][i] = 0 }
            mixed.append(left)
        }
        mixed.finish()
        let mixedPeak: Float = mixed.segmentURLs.first.flatMap(readMono).map { buffer in
            (0..<Int(buffer.frameLength)).reduce(0) { max($0, abs(buffer.floatChannelData![0][$1])) }
        } ?? -1
        check("a stereo track is mixed down to mono (converter.downmix)", mixedPeak > 0.2 && mixedPeak < 0.7,
              "peak \(mixedPeak)")

        // A writer that can't open its file says why.
        let broken = SegmentWriter(directory: dir.appending(path: "missing/deeper"), name: "mic", recordingStart: .now)
        if let tone = AVAudioPCMBuffer(pcmFormat: TrackFormat.format, frameCapacity: 1_600) {
            tone.frameLength = 1_600
            broken.append(tone)
        }
        broken.finish()
        check("a writer that can't write records \"Couldn't write audio: …\"",
              broken.failure?.hasPrefix("Couldn't write audio:") == true, broken.failure ?? "no failure")

        // A buffer that arrives after finish (a device callback in flight) is dropped.
        let late = SegmentWriter(directory: dir, name: "late", recordingStart: .now)
        if let tone = AVAudioPCMBuffer(pcmFormat: TrackFormat.format, frameCapacity: 1_600) {
            tone.frameLength = 1_600
            late.append(tone)
            late.finish()
            late.append(tone)
            late.finish()
        }
        check("a buffer after finish is dropped", late.framesWritten == 1_600 && late.segmentURLs.count == 1,
              "frames \(late.framesWritten)")
    }

    /// The after-call pass on two spoken tracks made with `say`: the call says two
    /// sentences from 6 s, I answer at 0 s, and my mic picks up the call's first sentence
    /// 2 s after the call track has it. Loads the speech model, so it runs only with
    /// APP_SELFTEST_AUDIO=1.
    private static func checkAfterCall(model: AppModel) async {
        let started = Date()
        let audio = Store.root.appending(path: "say")
        try? FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        let budget = "The budget review moves to Thursday afternoon at three."
        let clips = [
            ("mine", "Thanks everyone, I will send the revised plan to Jordan tomorrow morning."),
            ("budget", budget),
            ("launch", "Priya will share the launch checklist before the next meeting."),
        ]
        var spoken: [String: AVAudioPCMBuffer] = [:]
        for (key, text) in clips {
            let url = audio.appending(path: "\(key).caf")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-o", url.path, "--data-format=LEF32@16000", text]
            try? say.run()
            say.waitUntilExit()
            spoken[key] = readMono(url)
        }
        guard spoken.count == clips.count else {
            check("say makes the test speech", false, "got \(spoken.keys.sorted().joined(separator: ", "))")
            return
        }
        let meeting = Meeting(info: MeetingInfo(id: "selftest-aftercall", title: "Acme kickoff",
                                                start: Date(timeIntervalSince1970: 1_793_975_400),
                                                speakers: ["me": "Sam Rivera"]), notes: "Agenda")
        guard let folder = try? model.library.save(meeting) else { check("the test meeting is saved", false); return }
        let dir = folder.appending(path: MeetingFolder.audio)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // The call track starts 6 s in: the budget sentence at 6 s, the launch sentence at 12 s.
        // The mic track starts at 0: my sentence at 0 s, the budget sentence leaking in at 8 s.
        let system = SegmentWriter(directory: dir, name: "system", recordingStart: .now)
        write(timeline([(0, spoken["budget"]!), (6, spoken["launch"]!)]), to: system)
        let mic = SegmentWriter(directory: dir, name: "mic", recordingStart: .now)
        write(timeline([(0, spoken["mine"]!), (8, spoken["budget"]!)]), to: mic)
        try? Tracks(mic: Tracks.Track(startOffset: 0, seconds: Double(mic.framesWritten) / TrackFormat.sampleRate),
                    system: Tracks.Track(startOffset: 6, seconds: Double(system.framesWritten) / TrackFormat.sampleRate))
            .save(in: dir)

        do {
            let t = try await AfterCall.run(meetingID: meeting.id, library: model.library, transcriber: .shared,
                                            me: AppDefaults.meName)
            let mine = t.lines.filter { $0.side == .me }.map(\.text).joined(separator: " ")
            let theirs = t.lines.filter { $0.side == .them }.map(\.text).joined(separator: " ")
            let removed = t.removedEcho.map(\.text).joined(separator: " ")
            print("AFTERCALL me: \(mine)")
            print("AFTERCALL them: \(theirs)")
            print("AFTERCALL removed echo: \(removed)")
            check("the after-call pass hears my side", mine.lowercased().contains("revised plan"), mine)
            check("…and their side", theirs.lowercased().contains("budget") && theirs.lowercased().contains("checklist"), theirs)
            check("the call leaking into my mic is removed as echo",
                  removed.lowercased().contains("budget") && !mine.lowercased().contains("budget"), removed)
            check("their lines start on the recording's clock", (t.lines.first { $0.side == .them }?.start ?? 0) > 5.5)
            let md = (try? String(contentsOf: folder.appending(path: MeetingFolder.transcript), encoding: .utf8)) ?? ""
            check("transcript.md names the sides from the meeting",
                  md.contains("**Sam Rivera:**") && md.contains("**Them:**"), md)
            check("transcript.json reads back", model.library.readTranscript(id: meeting.id) == t)
            let info = model.library.meeting(id: meeting.id)
            check("meeting.json records the speech engine",
                  info?.info.asr?.engine == "parakeet" && info?.info.asr?.model == Transcriber.model)
            check("the notes are left alone", info?.notes == "Agenda")
        } catch {
            check("the after-call pass runs", false, error.localizedDescription)
        }
        print("AFTERCALL took \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        try? model.library.moveToTrash(meeting.id)
        try? FileManager.default.removeItem(at: audio)
        model.reload()
    }

    /// Recording from the window and the menu bar, with fake captures that feed made-up
    /// buffers through the real SegmentWriter: no device opens and nothing asks for a
    /// permission. The after-call pass is a stand-in that stitches the real segments and
    /// writes an empty transcript (APP_SELFTEST_AUDIO runs the real one on speech).
    /// The calendar connection (S-023, S-040) on made-up events, never the Mac's calendars:
    /// Home's Coming up, an event opening its meeting, and a recording titled after the
    /// event that's on.
    private static func checkCalendar(model: AppModel) async {
        let recorder = model.recorder
        let saved = (recorder.captures, recorder.permissionsReady, recorder.afterCall, model.calendar)
        defer { (recorder.captures, recorder.permissionsReady, recorder.afterCall, model.calendar) = saved }
        check("test runs start with no calendar access and never ask", model.calendarAccess == .notAsked && model.calendarEvents.isEmpty)

        let now = Date()
        let kickoff = CalendarEvent(id: "kickoff", title: "Acme kickoff", start: now.addingTimeInterval(-300), end: now.addingTimeInterval(1_500),
                                    attendees: ["Sam Rivera", "Priya Shah"], link: URL(string: "https://meet.google.com/abc-defg-hij"))
        let later = CalendarEvent(id: "review", title: "Design review", start: now.addingTimeInterval(86_400), end: now.addingTimeInterval(88_200),
                                  attendees: ["Jordan Lee"])
        let declined = CalendarEvent(id: "optional", title: "Optional sync", start: now.addingTimeInterval(60), end: now.addingTimeInterval(1_800), declined: true)
        model.calendar = .fixed([kickoff, later, declined])
        check("a connected calendar's events are read", model.calendarAccess == .allowed && model.calendarEvents.count == 3)
        model.now = now
        let shown = model.comingUp.flatMap(\.events).map(\.title)
        check("Coming up leaves out the declined event", shown.contains("Acme kickoff") && !shown.contains("Optional sync"), "\(shown)")

        model.closeSettings()
        model.showHome()
        let before = model.meetings.count
        model.open(event: later)
        let made = model.selectedMeeting
        check("clicking an event makes a meeting titled after it, with its attendees",
              model.meetings.count == before + 1 && made?.info.title == "Design review" && made?.info.attendees == ["Jordan Lee"]
              && made?.info.start == later.start)
        model.showHome()
        model.open(event: later)
        check("clicking it again opens the same meeting", model.meetings.count == before + 1 && model.selection == made?.id)
        if let id = made?.id { try? model.library.moveToTrash(id) }
        model.reload()

        recorder.captures = CaptureFactory(mic: { FakeCapture(channels: 1, level: 0.3) },
                                           system: { FakeCapture(channels: 2, level: 0.5) })
        recorder.permissionsReady = { true }
        recorder.afterCall = { [library = model.library] id, progress in
            try library.saveTranscript(TranscriptBuilder.build(me: [], them: [], engine: Transcriber.engineName), for: id)
            progress(1)
        }
        model.showHome()
        model.startRecording()
        await poll { recorder.isRecording }
        let recording = model.selectedMeeting
        check("a recording started during an event takes its title and attendees",
              recorder.isRecording && recording?.info.title == "Acme kickoff" && recording?.info.attendees == ["Sam Rivera", "Priya Shah"],
              "\(recording?.info.title ?? "none") \(recording?.info.attendees ?? [])")
        try? await Task.sleep(for: .milliseconds(400))
        recorder.stop()
        await poll(timeout: 10) { !recorder.isRecording && recorder.transcribingID == nil }
        if let id = recording?.id { try? model.library.moveToTrash(id) }

        model.calendar = .fixed([])
        model.startRecording()
        await poll { recorder.isRecording }
        check("with no event on, a recording is titled after the time",
              model.selectedMeeting?.info.title == RecordingRules.title(for: model.selectedMeeting?.info.start ?? now),
              model.selectedMeeting?.info.title ?? "none")
        let untitled = model.selection
        try? await Task.sleep(for: .milliseconds(400))
        recorder.stop()
        await poll(timeout: 10) { !recorder.isRecording && recorder.transcribingID == nil }
        if let untitled { try? model.library.moveToTrash(untitled) }
        model.reload()
        model.selection = nil
    }

    private static func checkRecording(model: AppModel) async {
        guard let main = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            check("the main window is open", false)
            return
        }
        let recorder = model.recorder
        let saved = (recorder.captures, recorder.permissionsReady, recorder.afterCall)
        defer { (recorder.captures, recorder.permissionsReady, recorder.afterCall) = saved }
        let calls = AfterCallCalls()
        recorder.captures = CaptureFactory(mic: { FakeCapture(channels: 1, level: 0.3) },
                                           system: { FakeCapture(channels: 2, level: 0.5) })
        recorder.afterCall = { [library = model.library] id, progress in
            calls.ids.append(id)
            while calls.hold { try await Task.sleep(for: .milliseconds(50)) }
            if calls.failNext {
                calls.failNext = false
                throw CocoaError(.fileReadCorruptFile)
            }
            guard let audio = library.audioURL(for: id) else { throw CocoaError(.fileNoSuchFile) }
            let stitched = try await AfterCall.stitch(in: audio)
            calls.stitched[id] = [stitched.mic, stitched.system].compactMap { $0 }.map(\.lastPathComponent)
            progress(0.5)
            try library.saveTranscript(TranscriptBuilder.build(me: [], them: [], engine: Transcriber.engineName), for: id)
            progress(1)
        }
        model.closeSettings()
        model.selection = nil
        func editor() -> NotesTextView? { main.contentView.flatMap(NotesTextView.find) }
        /// The ⇧⌘R item's title, after the File menu updates as it does when opened.
        func fileMenuTitle() -> String? {
            NSApp.mainMenu?.update()
            let file = NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu
            file.map { $0.delegate?.menuNeedsUpdate?($0) }
            return menuItem(key: "r", modifiers: [.shift, .command], in: NSApp.mainMenu)?.title
        }

        // A missing permission opens the sheet, never a prompt, and records nothing.
        recorder.permissionsReady = { false }
        let before = model.meetings.count
        model.startRecording()
        await poll { main.attachedSheet != nil }
        check("Start Recording without access opens the permissions sheet and records nothing",
              model.permissionsRequest == .startRecording && main.attachedSheet != nil && !recorder.isRecording
              && model.meetings.count == before,
              "request \(String(describing: model.permissionsRequest)), sheet \(main.attachedSheet != nil)")
        model.permissionsRequest = nil
        await poll { main.attachedSheet == nil }
        recorder.permissionsReady = { true }

        // Start Recording with nothing open: a new meeting titled with the date and time.
        model.startRecording()
        let first = recorder.meetingID
        let since = recorder.startedAt
        check("Start Recording makes a meeting titled with its date and time and opens it on My notes",
              recorder.isRecording && first != nil && model.selection == first && model.canvasMode == .notes
              && model.meetings.count == before + 1
              && model.selectedMeeting?.info.title == since.map { RecordingRules.title(for: $0) },
              "phase \(recorder.phase), title \(model.selectedMeeting?.info.title ?? "none")")
        if case .recording = recorder.phase {} else { check("the phase is recording", false, "\(recorder.phase)") }
        await poll { fileMenuTitle() == "Stop" }
        check("File > Start Recording reads Stop while recording", fileMenuTitle() == "Stop", fileMenuTitle() ?? "missing")
        check("a second Start Recording is refused while recording",
              (try? recorder.start(into: nil)) == nil && recorder.meetingID == first && model.meetings.count == before + 1)
        await poll { recorder.samples >= 3 && recorder.meter.levels.contains { $0 > 0.05 } }
        check("the live level is sampled about 10 times a second, never per buffer",
              recorder.samples >= 3 && recorder.meter.levels.contains { $0 > 0.05 },
              "samples \(recorder.samples), levels \(recorder.meter.levels)")

        await checkControls(model: model, main: main)

        // Notes typed while recording get a margin timestamp, kept beside the notes.
        await poll { editor() != nil }
        if let view = editor() {
            main.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            for c in "Budget moves to Thursday" { view.insertText(String(c), replacementRange: view.selectedRange()) }
        }
        await poll { editor()?.marginTimes?.time(for: "Budget moves to Thursday") != nil }
        let stamped = editor()?.marginTimes?.time(for: "Budget moves to Thursday")
        check("a note line typed while recording gets a timestamp in the margin, not in the text",
              stamped.map { $0 >= 0 && $0 < 30 } == true && editor()?.string == "Budget moves to Thursday"
              && editor()?.subviews.contains { $0 is MarginTimesView } == true,
              "time \(stamped.map { "\($0)" } ?? "none"), text \(editor()?.string.debugDescription ?? "none")")

        // Stop: files closed, tracks.json and the end time written, the after-call pass runs,
        // and the Transcript opens.
        model.startRecording()
        guard let id = first else { return }
        let audio = model.library.audioURL(for: id)
        let tracks = audio.map { Tracks.load(from: $0) }
        let files = audio.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        check("Stop closes the recording and writes tracks.json for both sides",
              !recorder.isRecording && (tracks?.mic?.seconds ?? 0) > 0 && (tracks?.system?.seconds ?? 0) > 0
              && files.contains(Tracks.fileName),
              "phase \(recorder.phase), tracks \(String(describing: tracks)), files \(files.sorted())")
        check("Stop sets the meeting's end", model.library.meeting(id: id)?.info.end != nil)
        await poll(timeout: 10) { recorder.phase == .idle }
        check("after Stop the after-call pass runs on the meeting and the phase returns to idle",
              calls.ids == [id] && recorder.phase == .idle && calls.stitched[id] == ["mic.caf", "system.caf"],
              "calls \(calls.ids), phase \(recorder.phase), stitched \(calls.stitched[id] ?? [])")
        check("the Transcript opens on its own when transcription is done",
              model.selection == id && model.canvasMode == .transcript, "mode \(model.canvasMode)")
        check("File > Stop reads Start Recording again", fileMenuTitle() == "Start Recording", fileMenuTitle() ?? "missing")
        await poll { model.library.readNoteTimes(for: id) != nil }
        check("the note's timestamps are saved beside it as notes-times.json",
              model.library.readNoteTimes(for: id)?.time(for: "Budget moves to Thursday") == stamped,
              "\(String(describing: model.library.readNoteTimes(for: id)))")
        model.show(.notes)
        await poll { editor()?.marginTimes != nil }
        check("the timestamps come back when the meeting is opened again",
              editor()?.marginTimes?.time(for: "Budget moves to Thursday") == stamped)

        // Start Recording records into an open meeting with no audio; with audio it starts a
        // new one. Quick Note always starts a new one.
        let fresh = model.newMeeting()
        model.startRecording()
        check("Start Recording records into the open meeting when it has no audio yet",
              fresh != nil && recorder.meetingID == fresh?.id, "recording \(recorder.meetingID ?? "none")")
        model.startRecording()
        await poll(timeout: 10) { recorder.phase == .idle }
        model.open(fresh?.id ?? "")
        model.startRecording()
        check("…and starts a new meeting when the open one already has audio",
              recorder.isRecording && recorder.meetingID != fresh?.id, "recording \(recorder.meetingID ?? "none")")
        model.startRecording()
        await poll(timeout: 10) { recorder.phase == .idle }
        let blank = model.newMeeting()
        model.quickNote()
        check("Quick Note always starts a new meeting", recorder.isRecording && recorder.meetingID != blank?.id)

        // A transcription that fails shows the reason with Retry; Retry runs it again.
        calls.failNext = true
        let failing = recorder.meetingID
        model.startRecording()
        await poll(timeout: 10) { if case .failed = recorder.phase { true } else { false } }
        let failedNotice = recorder.notice
        check("a failed transcription shows the reason in the banner with Retry",
              failedNotice?.message.hasPrefix("Couldn't transcribe this meeting:") == true && failedNotice?.retryMeetingID == failing,
              "phase \(recorder.phase), notice \(String(describing: failedNotice))")
        let callsBefore = calls.ids.count
        recorder.retry()
        await poll(timeout: 10) { recorder.phase == .idle }
        check("Retry runs the after-call pass again", calls.ids.count == callsBefore + 1 && calls.ids.last == failing
              && recorder.notice == nil && recorder.phase == .idle, "calls \(calls.ids.count - callsBefore), phase \(recorder.phase)")

        await checkPause(model: model, calls: calls)
        await checkRecordingFailures(model: model, calls: calls)

        // At launch: a meeting with segments and no transcript gets tracks.json and the pass.
        let cut = Meeting(info: MeetingInfo(title: "Acme kickoff", start: Date().addingTimeInterval(-3_600)), notes: "Agenda")
        if let folder = try? model.library.save(cut) {
            let dir = folder.appending(path: MeetingFolder.audio)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let writer = SegmentWriter(directory: dir, name: "mic", recordingStart: .now)
            FakeCapture.feed(writer, channels: 1, level: 0.3, seconds: 2)
            writer.finish()
        }
        model.reload()
        let queued = recorder.recoverInterrupted(library: model.library)
        await poll(timeout: 10) { recorder.phase == .idle && calls.ids.last == cut.id }
        let rebuilt = model.library.audioURL(for: cut.id).map { Tracks.load(from: $0) }
        check("an interrupted recording is found at launch, and only that one", queued == [cut.id], "\(queued)")
        check("…gets tracks.json from zero and the after-call pass",
              rebuilt?.mic == Tracks.Track(startOffset: 0, seconds: 0) && rebuilt?.system == nil && calls.ids.last == cut.id
              && model.library.meeting(id: cut.id)?.info.end != nil,
              "tracks \(String(describing: rebuilt)), calls \(calls.ids.suffix(1))")
        check("…with a banner when it's done", recorder.notice?.message == "Finished transcribing an interrupted recording",
              recorder.notice?.message ?? "none")
        recorder.dismissNotice()

        // Clean up the meetings this made.
        for meeting in model.meetings { try? model.library.moveToTrash(meeting.id) }
        model.selection = nil
        model.reload()
        model.show(.notes)
    }

    /// The recording controls on a live recording (fake captures): shown for the whole
    /// recording whichever window is key, a non-activating panel on every Space, 264 × 48,
    /// placed bottom center above the Dock, moved only by the grip (drag and arrow keys),
    /// remembered per display, kept on screen, hidden and shown from the menu bar. The screens
    /// are made up, so nothing depends on this Mac's displays.
    private static func checkControls(model: AppModel, main: NSWindow) async {
        guard let panel = model.controls else {
            check("the recording controls exist", false)
            return
        }
        let saved = (panel.screens, panel.preferredScreen)
        defer { (panel.screens, panel.preferredScreen) = saved }
        let a = BarPlacement.Screen(id: "A", visible: CGRect(x: 0, y: 80, width: 1440, height: 795)) // grid: ok a made-up screen
        let b = BarPlacement.Screen(id: "B", visible: CGRect(x: 1440, y: 0, width: 1920, height: 1055)) // grid: ok a made-up screen
        panel.screens = { [a, b] }
        panel.preferredScreen = { "A" }
        AppDefaults.shared.removeObject(forKey: RecordingPanel.positionsKey)
        AppDefaults.shared.removeObject(forKey: RecordingPanel.displayKey)

        main.makeKeyAndOrderFront(nil)
        panel.hideByUser()
        panel.showByUser()
        let window = panel.window as? NSPanel
        check("the recording controls show for the whole recording, Silvanus's window key or not",
              panel.isShowing && window?.isVisible == true && window?.level == .floating
              && window?.identifier == RecordingPanel.windowID)
        check("…as a non-activating panel on every Space and over full-screen apps",
              window.map { $0.styleMask.contains(.nonactivatingPanel) && $0.becomesKeyOnlyIfNeeded && !$0.hidesOnDeactivate
                  && $0.collectionBehavior.contains(.canJoinAllSpaces) && $0.collectionBehavior.contains(.fullScreenAuxiliary)
                  && !$0.isMovableByWindowBackground } == true)
        check("…titled \"Silvanus recording controls\" for VoiceOver",
              window?.title == "Silvanus recording controls" && window?.accessibilityLabel() == "Silvanus recording controls")
        let size = NSHostingView(rootView: RecordingControls(status: .recording(since: Date()), meter: LevelMeter())).fittingSize
        check("the bar is 264 × 48", size == NSSize(width: 264, height: 48), "\(size)")
        let paused = NSHostingView(rootView: RecordingControls(status: .paused(elapsed: 7199), meter: LevelMeter())).fittingSize
        check("…and stays 264 wide with the note and a long time", paused.width == 264 && paused.height > 48, "\(paused)")

        let home = BarPlacement.defaultOrigin(size: panel.barFrame.size, in: a.visible, inset: Space.lg)
        check("they start bottom center above the Dock on the main window's display",
              panel.barOrigin == home && home == NSPoint(x: 588, y: 96), "\(panel.barOrigin)")
        panel.dragBegan(at: NSPoint(x: 600, y: 120))
        panel.dragMoved(to: NSPoint(x: 700, y: 300))
        panel.dragEnded()
        let dragged = NSPoint(x: 688, y: 276)
        check("dragging the grip moves them and saves the spot for that display",
              panel.barOrigin == dragged && RecordingPanel.savedPositions()["A"] == dragged && RecordingPanel.savedDisplay() == "A",
              "\(panel.barOrigin), saved \(RecordingPanel.savedPositions())")
        panel.dragBegan(at: NSPoint(x: 600, y: 120))
        panel.dragMoved(to: NSPoint(x: 600, y: 1_000))
        check("a drag past the menu bar stops at the visible frame", panel.barFrame.maxY == a.visible.maxY,
              "\(panel.barFrame)")
        panel.dragMoved(to: NSPoint(x: 700, y: 300))
        panel.dragEnded()
        let base = panel.barOrigin
        await poll { window?.contentView.flatMap(findGrip) != nil }
        if let grip = window?.contentView.flatMap(findGrip),
           let left = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                       context: nil, characters: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
                                       charactersIgnoringModifiers: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
                                       isARepeat: false, keyCode: 123),
           let up = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0,
                                     context: nil, characters: String(UnicodeScalar(NSUpArrowFunctionKey)!),
                                     charactersIgnoringModifiers: String(UnicodeScalar(NSUpArrowFunctionKey)!),
                                     isARepeat: false, keyCode: 126) {
            grip.keyDown(with: left)
            grip.keyDown(with: up)
            check("the focused grip moves them with the arrow keys, farther with Shift",
                  panel.barOrigin == NSPoint(x: base.x - 8, y: base.y + 24), "\(panel.barOrigin)")
            check("the grip is the one drag region, named for VoiceOver",
                  grip.accessibilityLabel() == "Move recording controls" && !grip.mouseDownCanMoveWindow
                  && grip.acceptsFirstMouse(for: nil))
        } else {
            check("the grip is in the controls", false)
        }
        let afterKeys = panel.barOrigin
        panel.dragBegan(at: NSPoint(x: 0, y: 0))
        panel.dragMoved(to: NSPoint(x: 1_700, y: -100))
        panel.dragEnded()
        let onB = panel.barOrigin
        check("dragged onto another display, the spot is saved for that one",
              RecordingPanel.savedDisplay() == "B" && RecordingPanel.savedPositions()["B"] == onB && b.visible.contains(panel.barFrame),
              "\(onB), \(RecordingPanel.savedPositions())")
        panel.hideByUser()
        check("Hide Recording Controls hides them, and the menu bar offers Show Recording Controls",
              !panel.isShowing && menuBarTitles(model: model).contains("Show Recording Controls") && model.recorder.isRecording)
        panel.showByUser()
        check("…they come back where they were left", panel.isShowing && panel.barOrigin == onB, "\(panel.barOrigin)")
        panel.screens = { [a] }
        panel.screensChanged()
        check("a display that goes away sends them to the main window's display, at its saved spot",
              a.visible.contains(panel.barFrame) && panel.barOrigin == afterKeys, "\(panel.barFrame)")
        let shrunk = BarPlacement.Screen(id: "A", visible: CGRect(x: 0, y: 80, width: 600, height: 300))
        panel.screens = { [shrunk] }
        panel.screensChanged()
        check("a smaller resolution pulls them back inside", shrunk.visible.contains(panel.barFrame), "\(panel.barFrame)")
        panel.screens = { [a, b] }
        check("the menu bar has Reset Recording Controls Position, and so does the Window menu",
              menuBarTitles(model: model).contains("Reset Recording Controls Position")
              && menuItem(title: "Reset Recording Controls Position", in: NSApp.mainMenu) != nil)
        panel.resetPosition()
        check("Reset puts them back bottom center on the main window's display",
              panel.barOrigin == home && RecordingPanel.savedPositions()["A"] == nil, "\(panel.barOrigin)")
    }

    private static func findGrip(_ view: NSView) -> GripView? {
        if let grip = view as? GripView { return grip }
        for subview in view.subviews { if let grip = findGrip(subview) { return grip } }
        return nil
    }

    /// Pause and Resume on a recording with fake captures: Pause releases both devices and
    /// Resume starts them again in the same tracks, the time holds (and the notes' times
    /// with it), the controls show the note and flat bars, and the same meeting goes on.
    /// Through several pauses, a microphone with ~30 ms buffers and call audio with 10 ms
    /// buffers stay within 50 ms of each other. Stop while paused finalizes. A microphone
    /// that won't restart is Audio lost; a failure while paused retries back to Paused.
    private static func checkPause(model: AppModel, calls: AfterCallCalls) async {
        let recorder = model.recorder
        final class Made { var mic: [FakeCapture] = []; var system: [FakeCapture] = [] }
        let made = Made()
        func fakes(mic mode: FakeCapture.Mode = .tone) {
            recorder.captures = CaptureFactory(
                mic: { let f = FakeCapture(channels: 1, level: 0.3, mode: mode, chunk: 0.03, burst: 0); made.mic.append(f); return f },
                system: { let f = FakeCapture(channels: 2, level: 0.5, chunk: 0.01, burst: 0); made.system.append(f); return f })
        }
        fakes()
        let started = Date()
        model.quickNote()
        guard let id = recorder.meetingID else {
            check("the pause recording starts", false)
            return
        }
        await poll { recorder.meter.levels.contains { $0 > 0.05 } }
        check("the level bars follow the captured audio (both tracks, never a microphone of their own)",
              recorder.meter.levels.contains { $0 > 0.05 }, "\(recorder.meter.levels)")
        try? await Task.sleep(for: .milliseconds(300))
        let barBefore = model.controls?.barOrigin
        recorder.pause()
        let held = recorder.elapsed(for: id)
        let pausedTitles = menuBarTitles(model: model)
        check("Pause releases both devices", made.mic.last?.isRunning == false && made.system.last?.isRunning == false)
        try? await Task.sleep(for: .milliseconds(1_500))
        check("Pause holds the time", recorder.mode == .paused && recorder.elapsed(for: id) == held && held != nil,
              "mode \(recorder.mode)")
        check("…the bars go flat", recorder.meter.levels.allSatisfy { $0 == 0 }, "\(recorder.meter.levels)")
        check("…the menu bar says Paused, with Resume and Stop", pausedTitles.starts(with: ["Paused", "Resume", "Stop"]),
              pausedTitles.joined(separator: ", "))
        check("…VoiceOver hears \"Paused. Audio isn't being saved.\"",
              model.controls?.lastAnnouncement == "Paused. Audio isn't being saved.", model.controls?.lastAnnouncement ?? "none")
        check("…and the note shows above the bar while the bar holds still",
              (model.controls?.frame?.height ?? 0) > Metric.barHeight + 2 * Metric.barWindowMargin + Metric.barNoteGap
              && model.controls?.barOrigin == barBefore)
        recorder.resume()
        check("Resume starts both devices again in the same tracks",
              made.mic.count == 1 && made.system.count == 1 && made.mic[0].isRunning && made.system[0].isRunning
              && made.mic[0].starts == 2 && made.system[0].starts == 2)
        try? await Task.sleep(for: .milliseconds(500))
        let after = recorder.elapsed(for: id) ?? 0
        let wall = Date().timeIntervalSince(started)
        check("Resume goes on in the same meeting, and the time leaves the pause out",
              recorder.mode == .recording && recorder.meetingID == id && after > (held ?? 0) && after < wall - 1.3,
              "captured \(after), wall \(wall)")
        check("the notes' margin times use the captured time", recorder.elapsed(for: id).map { $0 < wall - 1.3 } == true)
        for _ in 0..<3 {
            recorder.pause()
            try? await Task.sleep(for: .milliseconds(300))
            recorder.resume()
            try? await Task.sleep(for: .milliseconds(700))
        }
        recorder.pause()
        let wallAtStop = Date().timeIntervalSince(started)
        model.startRecording()
        let tracks = model.library.audioURL(for: id).map { Tracks.load(from: $0) }
        let mic = tracks?.mic?.seconds ?? 0, system = tracks?.system?.seconds ?? 0
        check("Stop while paused finalizes the meeting", !recorder.isRecording && mic > 0, "\(recorder.phase)")
        check("nothing heard while paused is saved, on either track", mic < wallAtStop - 1.5 && system < wallAtStop - 1.5,
              "mic \(mic), system \(system), wall \(wallAtStop)")
        check("…and after four pauses, tracks with different buffer sizes stay within 50 ms",
              abs((tracks?.mic?.startOffset ?? 9) + mic - (tracks?.system?.startOffset ?? -9) - system) < 0.05,
              "\(String(describing: tracks))")
        await poll(timeout: 10) { !recorder.hasWork }

        // A microphone that won't start again on Resume: Audio lost, and Retry records on.
        fakes(mic: .failsOnRestart)
        model.quickNote()
        try? await Task.sleep(for: .milliseconds(300))
        recorder.pause()
        recorder.resume()
        let lost: String? = if case let .interrupted(_, reason) = recorder.phase { reason } else { nil }
        check("a microphone that won't restart on Resume is Audio lost",
              lost?.hasPrefix("Couldn't restart the microphone") == true, lost ?? "\(recorder.phase)")
        fakes()
        recorder.retryCapture()
        check("…and Retry records on", recorder.mode == .recording && made.system.last?.isRunning == true, "\(recorder.mode)")

        // A failure that comes while paused: Retry goes back to Paused, devices released.
        recorder.pause()
        recorder.failMicForChecks("Couldn't restart the microphone: The test device went away.")
        await poll { recorder.mode == .interrupted }
        recorder.retryCapture()
        check("Retry after a failure while paused returns to Paused", recorder.mode == .paused
              && made.mic.last?.isRunning == false && made.system.last?.isRunning == false, "\(recorder.mode)")
        model.startRecording()
        await poll(timeout: 10) { !recorder.hasWork }
    }

    /// Stop when the call ends, with the fake call probe driving the real detector: a
    /// recording started during a call counts down once the call app has let go of the
    /// microphone (shortened from 15 s and 10 s), Keep recording holds until a new call, call
    /// input coming back cancels, Pause holds it off, Quick Note never stops, the setting
    /// turns it off, and at 0 the meeting is closed and transcribed exactly as Stop does.
    private static func checkStopWhenCallEnds(model: AppModel, calls: AfterCallCalls,
                                              idle: () async -> Void) async {
        let recorder = model.recorder
        recorder.captures = CaptureFactory(mic: { FakeCapture(channels: 1, level: 0.3, mode: .tone) },
                                           system: { FakeCapture(channels: 2, level: 0.5, mode: .tone) })
        // `inCall` uses the microphone and plays; `muted` only plays.
        final class Fake { var inCall = false; var muted = false }
        let fake = Fake()
        let detector = model.makeDetector(probe: .init(callAppsUsingInput: { fake.inCall ? ["us.zoom.xos"] : [] },
                                                       callAppsUsingOutput: { fake.inCall || fake.muted ? ["us.zoom.xos"] : [] },
                                                       micInUseElsewhere: { fake.inCall },
                                                       runningCallApps: { ["us.zoom.xos"] }))
        let probe = detector.probe
        recorder.callAppProbe = { probe.callInProgress(recording: false) }
        let saved = (recorder.callEndQuiet, recorder.callEndCountdown)
        recorder.callEndQuiet = 0.4
        recorder.callEndCountdown = 0.8
        defer {
            recorder.callEndQuiet = saved.0
            recorder.callEndCountdown = saved.1
            recorder.callAppProbe = { false }
            recorder.callAppRunning = false
        }
        check("Stop when the call ends starts on", model.stopWhenCallEnds && AppDefaults.stopWhenCallEnds)

        // A recording started during a call; the call ends.
        fake.inCall = true
        detector.poll()
        model.startRecording()
        let call = recorder.meetingID
        try? await Task.sleep(for: .milliseconds(700))
        check("while the call app uses the microphone, there's no countdown",
              recorder.isRecording && recorder.callEndStopAt == nil && recorder.callAppAtStart)
        // Muted: the call app lets go of the microphone but still plays the call.
        fake.inCall = false
        fake.muted = true
        detector.poll()
        try? await Task.sleep(for: .milliseconds(1_800))
        check("muted (the call app playing, not using the microphone) never counts down",
              recorder.isRecording && recorder.callEndStopAt == nil)
        fake.muted = false
        fake.inCall = false
        detector.poll()
        await poll { recorder.callEndStopAt != nil }
        check("once the call app lets go of the microphone, the controls count down",
              recorder.isRecording && recorder.callEndStopAt != nil)
        // The note's schedule ticks once a second from the moment it shows: 10, 9, 8.
        let shown = Date()
        let tenOut = shown.addingTimeInterval(CallEndStop.countdown)
        let ticks = RecordingControls.countdownSchedule(stopAt: tenOut).entries(from: shown, mode: .normal)
            .prefix(3).map { RecordingControls.countdownText(stopAt: tenOut, at: $0) }
        check("the countdown note ticks 10, 9, 8, a second apart",
              ticks == [10, 9, 8].map { RecordingWords.callEndedNote(seconds: $0) }, ticks.joined(separator: " | "))
        await poll { model.controls?.lastAnnouncement?.hasPrefix(RecordingWords.callEnded) == true }
        check("…saying \"Call ended. Stopping in 10 seconds.\" in the note above the bar, once to VoiceOver",
              RecordingWords.callEndedNote(seconds: 10) == "Call ended. Stopping in 10 seconds."
              && model.controls?.lastAnnouncement?.hasPrefix(RecordingWords.callEnded) == true,
              model.controls?.lastAnnouncement ?? "none")
        // The call comes back: the countdown goes.
        fake.inCall = true
        detector.poll()
        await poll { recorder.callEndStopAt == nil }
        check("call input coming back cancels the countdown", recorder.isRecording && recorder.callEndStopAt == nil)
        // Pause: nothing counts.
        fake.inCall = false
        detector.poll()
        recorder.pause()
        try? await Task.sleep(for: .milliseconds(1_500))
        check("while paused there's no countdown, and it never stops", recorder.mode == .paused
              && recorder.callEndStopAt == nil)
        recorder.resume()
        await poll { recorder.callEndStopAt != nil }
        // Keep recording: no countdown until a new call starts.
        recorder.keepRecording()
        try? await Task.sleep(for: .milliseconds(1_500))
        check("Keep recording keeps it recording with no countdown", recorder.isRecording
              && recorder.meetingID == call && recorder.callEndStopAt == nil)
        fake.inCall = true
        detector.poll()
        try? await Task.sleep(for: .milliseconds(200))
        fake.inCall = false
        detector.poll()
        let before = calls.ids.count
        await poll(timeout: 4) { !recorder.isRecording }
        check("…until a new call starts and ends: then at 0 it stops on its own",
              !recorder.isRecording && recorder.callEndStopAt == nil, "\(recorder.phase)")
        await idle()
        let tracks = call.flatMap { model.library.audioURL(for: $0) }.map { Tracks.load(from: $0) }
        let ended = call.flatMap { model.library.meeting(id: $0) }?.info.end
        check("…and the meeting is closed and transcribed exactly as Stop does",
              calls.ids.count == before + 1 && calls.ids.last == call && (tracks?.mic?.seconds ?? 0) > 0 && ended != nil,
              "calls \(calls.ids.count - before), \(String(describing: tracks))")

        // Quick Note during a call never stops on its own.
        fake.inCall = true
        detector.poll()
        model.quickNote()
        fake.inCall = false
        detector.poll()
        try? await Task.sleep(for: .milliseconds(1_800))
        check("Quick Note never stops when a call ends", recorder.isRecording && recorder.callEndStopAt == nil)
        model.startRecording()
        await idle()

        // No call at the start: never.
        model.startRecording()
        try? await Task.sleep(for: .milliseconds(1_800))
        check("a recording with no call at its start never stops on its own", recorder.isRecording
              && !recorder.callAppAtStart && recorder.callEndStopAt == nil)
        model.startRecording()
        await idle()

        // The setting off: never.
        model.stopWhenCallEnds = false
        check("turning Stop when the call ends off is saved",
              AppDefaults.shared.object(forKey: AppDefaults.stopWhenCallEndsKey) as? Bool == false)
        fake.inCall = true
        detector.poll()
        model.startRecording()
        fake.inCall = false
        detector.poll()
        try? await Task.sleep(for: .milliseconds(1_800))
        check("with it off, a call that ends never stops the recording", recorder.isRecording
              && recorder.callEndStopAt == nil)
        model.startRecording()
        await idle()
        model.stopWhenCallEnds = true
    }

    /// The call detector with a fake probe: "Meeting detected" once per call, naming the app
    /// only when it's known, never with no call app, never while recording, not when the
    /// setting is off, and gone when the call ends; Record Meeting in the menu bar meanwhile.
    private static func checkMeetingDetection(model: AppModel) async {
        // `mic` is any process using input; `apps` the call apps among them.
        final class Fake { var mic = false; var apps: Set<String> = [] }
        let fake = Fake()
        let detector = model.makeDetector(probe: .init(callAppsUsingInput: { fake.mic ? fake.apps : [] },
                                                       micInUseElsewhere: { fake.mic }, runningCallApps: { fake.apps }))
        guard let prompt = model.meetingPrompt else {
            check("the Meeting detected prompt exists", false)
            return
        }
        func release() {
            fake.mic = false
            for _ in 0..<5 { detector.poll() }
        }
        check("Prompt when a meeting starts starts on", model.promptOnMeeting && AppDefaults.promptOnMeeting)
        let shown = prompt.shown
        fake.mic = true
        detector.poll()
        detector.poll()
        check("the microphone in use with no call app shows no prompt", !prompt.isShowing && prompt.shown == shown)
        fake.apps = ["us.zoom.xos"]
        detector.displayName = { _ in "Callbox" }
        detector.poll()
        check("a call app using the microphone shows \"Meeting detected\", naming the app",
              prompt.isShowing && prompt.shown == shown + 1 && prompt.appName == "Callbox"
              && model.detectedCall == DetectedCall(appName: "Callbox"),
              "app \(prompt.appName ?? "none")")
        let menuTitles = { menuBarTitles(model: model) }
        check("…and the menu bar offers Record Meeting while it waits", menuTitles().contains("Record Meeting"),
              menuTitles().joined(separator: ", "))
        prompt.hide()
        check("Not now hides the prompt for this call, and Record Meeting stays in the menu bar",
              !prompt.isShowing && model.detectedCall != nil && menuTitles().contains("Record Meeting"))
        detector.poll()
        detector.poll()
        check("…once per call", prompt.shown == shown + 1, "shown \(prompt.shown - shown)")
        check("…and the recorder hears that a call app runs", model.recorder.callAppRunning)
        release()
        check("the call ending takes the offer away", model.detectedCall == nil && !prompt.isShowing
              && !menuTitles().contains("Record Meeting"))
        // Two call apps at once, or only the fallback's evidence: no app is named.
        fake.mic = true
        fake.apps = ["us.zoom.xos", "com.apple.FaceTime"]
        detector.poll()
        check("with no one app known to use the microphone, it asks \"Microphone in use\" instead",
              prompt.isShowing && prompt.appName == nil
              && RecordingWords.prompt(appName: prompt.appName).title == "Microphone in use")
        prompt.hide()
        fake.apps = ["us.zoom.xos"]
        release()
        let base = prompt.shown
        model.promptOnMeeting = false
        check("turning the prompt off is saved", AppDefaults.shared.object(forKey: AppDefaults.promptOnMeetingKey) as? Bool == false)
        fake.mic = true
        detector.poll()
        check("with Prompt when a meeting starts off, nothing shows", !prompt.isShowing && prompt.shown == base)
        model.promptOnMeeting = true
        release()
        model.recorder.force(.recording(since: Date()))
        fake.mic = true
        detector.poll()
        check("nothing shows while Silvanus records", !prompt.isShowing && prompt.shown == base)
        model.recorder.force(.idle)
        detector.poll()
        check("…nor after it stops mid-call", !prompt.isShowing && prompt.shown == base)
        release()
        fake.mic = true
        detector.poll()
        try? await Task.sleep(for: .milliseconds(300))
        check("the prompt has no countdown: it stays until it's answered or the call ends", prompt.isShowing)
        release()
        check("…and a prompt for a call that ended goes", !prompt.isShowing)
        // A browser open but not using input (an in-person meeting): no call.
        let chromeOpen = CallDetector.Probe(callAppsUsingInput: { [] }, micInUseElsewhere: { true },
                                            runningCallApps: { ["com.google.Chrome"] })
        check("a call app that's open but not using input isn't a call",
              !chromeOpen.callInProgress(recording: false) && !chromeOpen.callInProgress(recording: true))
        let noList = CallDetector.Probe(callAppsUsingInput: { nil }, micInUseElsewhere: { true },
                                        runningCallApps: { ["us.zoom.xos"] })
        check("without the process list, the input device running while a call app runs is a call",
              noList.callInProgress(recording: false))
        let live = CallDetector.liveCallAppAudio()
        check("Core Audio's process list can be read", live != nil)
        model.recorder.callAppRunning = false
    }

    /// MicCapture through a device switch, on a fake engine with fake configuration-change
    /// notifications: no device opens.
    private static func checkMicRestarts() async {
        let dir = Store.root.appending(path: "mic-restarts")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func change(_ engine: FakeMicEngine) {
            NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine.notificationObject)
        }

        // An input with no usable format throws instead of reaching installTap.
        let none = FakeMicEngine()
        none.formatAvailable = false
        var thrown: Error?
        do { try MicCapture(engine: none).start(into: SegmentWriter(directory: dir, name: "none", recordingStart: .now)) } catch { thrown = error }
        check("a microphone with no usable format throws instead of installing a tap",
              (thrown as? CaptureError).map { if case .noInput = $0 { true } else { false } } == true && none.installs == 0)

        // A change that lands during Stop leaves the engine stopped, with no tap.
        let racing = FakeMicEngine()
        racing.startDelay = 0.05
        let racingMic = MicCapture(engine: racing)
        try? racingMic.start(into: SegmentWriter(directory: dir, name: "racing", recordingStart: .now))
        change(racing)
        racingMic.stop()
        change(racing)
        try? await Task.sleep(for: .milliseconds(300))
        check("a device change during Stop leaves the engine stopped with no tap",
              !racing.running && racing.taps == 0, "running \(racing.running), taps \(racing.taps)")

        // Two changes back to back: one tap at a time, the engine running, a new segment each.
        let twice = FakeMicEngine()
        let twiceMic = MicCapture(engine: twice)
        try? twiceMic.start(into: SegmentWriter(directory: dir, name: "twice", recordingStart: .now))
        change(twice)
        change(twice)
        twiceMic.settle()
        check("two device changes back to back install one tap and keep the engine running",
              twice.taps == 1 && twice.maxTaps == 1 && twice.running && twiceMic.restarts == 2,
              "taps \(twice.taps), most \(twice.maxTaps), running \(twice.running), restarts \(twiceMic.restarts)")
        twiceMic.stop()

        // A Bluetooth switch: no input for a moment, then it comes back.
        let bluetooth = FakeMicEngine()
        let bluetoothMic = MicCapture(engine: bluetooth)
        bluetoothMic.retryDelay = 0.05
        try? bluetoothMic.start(into: SegmentWriter(directory: dir, name: "bluetooth", recordingStart: .now))
        bluetooth.formatAvailable = false
        change(bluetooth)
        try? await Task.sleep(for: .milliseconds(80))
        bluetooth.formatAvailable = true
        try? await Task.sleep(for: .milliseconds(300))
        bluetoothMic.settle()
        check("a microphone that's briefly gone (a Bluetooth switch) is retried until it's back",
              bluetooth.running && bluetooth.taps == 1, "running \(bluetooth.running), taps \(bluetooth.taps)")
        bluetoothMic.stop()

        // One that never comes back stops the recording with a reason.
        let gone = FakeMicEngine()
        let goneMic = MicCapture(engine: gone)
        goneMic.retryDelay = 0.02
        let goneWriter = SegmentWriter(directory: dir, name: "gone", recordingStart: .now)
        try? goneMic.start(into: goneWriter)
        gone.formatAvailable = false
        change(gone)
        await poll { goneWriter.failure != nil }
        check("a microphone that doesn't come back fails with \"Couldn't restart the microphone: …\"",
              goneWriter.failure?.hasPrefix("Couldn't restart the microphone:") == true && gone.taps == 0,
              goneWriter.failure ?? "no failure")
        goneMic.stop()

        // Appends racing finish never open a segment after the close.
        let race = SegmentWriter(directory: dir, name: "race", recordingStart: .now)
        if let tone = AVAudioPCMBuffer(pcmFormat: TrackFormat.format, frameCapacity: 160) {
            tone.frameLength = 160
            // The writer copies each buffer, so sharing one across threads is safe here.
            nonisolated final class Shared: @unchecked Sendable { let buffer: AVAudioPCMBuffer; init(_ b: AVAudioPCMBuffer) { buffer = b } }
            let shared = Shared(tone)
            DispatchQueue.concurrentPerform(iterations: 50) { i in
                if i == 25 { race.finish() } else { race.append(shared.buffer) }
            }
            race.finish()
            let frames = race.framesWritten
            let segments = race.segmentURLs.count
            for _ in 0..<10 { race.append(tone) }
            try? await Task.sleep(for: .milliseconds(100))
            check("appends racing finish open no segment after the close",
                  race.framesWritten == frames && race.segmentURLs.count == segments && segments <= 1,
                  "frames \(frames) -> \(race.framesWritten), segments \(segments) -> \(race.segmentURLs.count)")
        }
    }

    /// What goes wrong live, acted out with fake captures: a microphone that won't start or
    /// fails mid-call, call audio that fails, a microphone that changes or goes quiet (never a
    /// warning), Stop before any audio, Stop when the call ends (with the fake call probe),
    /// Move to Trash while busy, the retry cap, ⌘Q while recording, and the permissions
    /// sheet's Start.
    private static func checkRecordingFailures(model: AppModel, calls: AfterCallCalls) async {
        let recorder = model.recorder
        func captures(mic: FakeCapture.Mode = .tone, system: FakeCapture.Mode = .tone) {
            recorder.captures = CaptureFactory(mic: { FakeCapture(channels: 1, level: 0.3, mode: mic) },
                                               system: { FakeCapture(channels: 2, level: 0.5, mode: system) })
        }
        func audioOf(_ id: String?) -> URL? { id.flatMap { model.library.audioURL(for: $0) } }
        func idle() async { await poll(timeout: 10) { !recorder.hasWork } }

        // 1. A microphone that won't start: the banner says why, and the meeting made for it goes.
        captures(mic: .failsToStart)
        let count = model.meetings.count
        model.quickNote()
        check("a microphone that won't start says why, with nothing to retry, and leaves no empty meeting",
              recorder.notice?.message.hasPrefix("Couldn't start recording:") == true && recorder.notice?.retryMeetingID == nil
              && !recorder.isRecording && model.meetings.count == count && model.selection == nil,
              "notice \(String(describing: recorder.notice)), meetings \(count) -> \(model.meetings.count)")
        recorder.dismissNotice()

        // 2. The microphone's writer fails mid-call: "Audio lost", the time holds, nothing is
        // saved, and Retry brings it back in the same meeting.
        captures(mic: .failsWriting)
        model.quickNote()
        let broken = recorder.meetingID ?? ""
        await poll { recorder.mode == .interrupted }
        let held = recorder.elapsed(for: broken)
        try? await Task.sleep(for: .milliseconds(400))
        check("a microphone that fails is \"Audio lost\": still recording, the time held",
              recorder.mode == .interrupted && recorder.isRecording && held != nil && recorder.elapsed(for: broken) == held,
              "mode \(recorder.mode), held \(held.map { "\($0)" } ?? "none") now \(recorder.elapsed(for: broken).map { "\($0)" } ?? "none")")
        let lostTitles = menuBarTitles(model: model)
        check("…the controls stay up, and the menu bar says \"Audio lost\" with Retry and Stop",
              model.controls?.isShowing == true && lostTitles.starts(with: ["Audio lost", "Retry", "Stop"]),
              lostTitles.joined(separator: ", "))
        check("…and VoiceOver hears it once", model.controls?.lastAnnouncement?.hasPrefix("Audio lost") == true,
              model.controls?.lastAnnouncement ?? "none")
        recorder.pause()
        check("Pause isn't allowed while audio is lost", recorder.mode == .interrupted)
        captures(mic: .failsToStart)
        recorder.retryCapture()
        let stillLost: String? = if case let .interrupted(_, reason) = recorder.phase { reason } else { nil }
        check("Retry while the microphone can't start stays \"Audio lost\", with the new reason",
              stillLost?.hasPrefix("Couldn't restart the microphone") == true, stillLost ?? "\(recorder.phase)")
        captures()
        recorder.retryCapture()
        // The fakes deliver half a second ahead of the clock; lining up drops that first.
        try? await Task.sleep(for: .milliseconds(900))
        check("Retry that works records on in the same meeting, and the time goes on from where it held",
              recorder.mode == .recording && recorder.meetingID == broken
              && (recorder.elapsed(for: broken) ?? 0) > (held ?? 0),
              "mode \(recorder.mode)")
        model.startRecording()
        let brokenFiles = audioOf(broken).map { SegmentWriter.segments(named: "mic", in: $0).count } ?? 0
        check("…and the microphone goes on in a new segment of the same track", brokenFiles >= 2, "segments \(brokenFiles)")
        await idle()
        check("…and the meeting is transcribed after Stop", calls.ids.last == broken, "calls \(calls.ids.suffix(1))")

        // 3. Call audio fails mid-call: the microphone records on, and says so ("Mic only").
        captures(system: .failsWriting)
        model.quickNote()
        let micOnly = recorder.meetingID
        await poll { recorder.callAudioDown != nil }
        check("call audio that fails drops to the microphone alone and keeps recording, saying so",
              recorder.mode == .recording && recorder.callAudioDown != nil && recorder.warning?.hasPrefix(Recorder.micOnly) == true
              && menuBarTitles(model: model).contains("Retry Call Audio"),
              "mode \(recorder.mode), warning \(recorder.warning ?? "none")")
        captures()
        recorder.retryCallAudio()
        check("Retry Call Audio brings call audio back in its track", recorder.callAudioDown == nil
              && recorder.warning?.hasPrefix(Recorder.micOnly) != true, recorder.warning ?? "none")
        try? await Task.sleep(for: .milliseconds(900))
        model.startRecording()
        let micOnlyTracks = audioOf(micOnly).map { Tracks.load(from: $0) }
        let micOnlySystem = audioOf(micOnly).map { SegmentWriter.segments(named: "system", in: $0).count } ?? 0
        check("…and tracks.json keeps both sides, call audio in two segments of one track",
              (micOnlyTracks?.system?.seconds ?? 0) > 0 && micOnlySystem >= 2,
              "\(String(describing: micOnlyTracks)), system segments \(micOnlySystem)")
        await idle()

        // 4. The microphone changes mid-call: a new segment in the same track. A quiet
        // microphone is normal: no warning.
        captures(mic: .changesDevice)
        model.quickNote()
        let changed = recorder.meetingID
        try? await Task.sleep(for: .milliseconds(1_500))
        model.startRecording()
        let micSegments = audioOf(changed).map { SegmentWriter.segments(named: "mic", in: $0).count } ?? 0
        let micSeconds = audioOf(changed).map { Tracks.load(from: $0) }?.mic?.seconds ?? 0
        check("a microphone that changes goes on in a new segment of the same track",
              micSegments >= 2 && micSeconds > 0.9, "segments \(micSegments), seconds \(micSeconds)")
        await idle()
        captures(mic: .silent)
        model.quickNote()
        try? await Task.sleep(for: .milliseconds(800))
        check("a microphone that stays silent shows no warning (silence is normal)", recorder.warning == nil,
              recorder.warning ?? "none")
        check("…and silence is never \"Audio lost\"", recorder.mode == .recording, "\(recorder.mode)")

        // 5. Stop before any audio arrives: nothing to transcribe, and the banner says so.
        captures(mic: .silent, system: .silent)
        let before = calls.ids.count
        model.startRecording()          // stops the silent-mic recording
        await idle()
        let before2 = calls.ids.count
        model.quickNote()
        model.startRecording()
        await idle()
        check("Stop before any audio transcribes nothing and says \"Nothing was recorded.\"",
              calls.ids.count == before2 && recorder.notice?.message == Recorder.nothingRecorded && recorder.phase == .idle,
              "calls \(calls.ids.count - before), notice \(recorder.notice?.message ?? "none")")
        recorder.dismissNotice()

        // 5b. Call audio that stays silent during a call is normal too: no warning.
        captures(system: .silent)
        recorder.callAppProbe = { true }
        recorder.stopWhenCallEnds = { false }
        model.startRecording()
        try? await Task.sleep(for: .milliseconds(800))
        check("silent call audio during a call shows no warning", recorder.isRecording && recorder.warning == nil,
              recorder.warning ?? "none")
        model.startRecording()
        await idle()
        recorder.stopWhenCallEnds = { AppDefaults.stopWhenCallEnds }

        // 5c. Stop when the call ends, with the fake call probe: the call app lets go of the
        // microphone, the controls count down with Keep recording, and at 0 it stops like Stop.
        await checkStopWhenCallEnds(model: model, calls: calls, idle: idle)
        captures()

        // 6. Move to Trash is off for the recording meeting and the one transcribing.
        captures()
        model.quickNote()
        let busy = recorder.meetingID ?? ""
        model.trash(busy)
        let trashItem: () -> NSMenuItem? = {
            let menu = NSApp.mainMenu?.items.first { $0.title == "Meeting" }?.submenu
            menu.map { $0.delegate?.menuNeedsUpdate?($0) }
            NSApp.mainMenu?.update()
            return menuItem(title: "Move to Trash", in: menu)
        }
        await poll { trashItem()?.isEnabled == false }
        check("Move to Trash is off for the meeting that records, with a reason",
              !model.canTrash(busy) && model.meetings.contains { $0.id == busy } && trashItem()?.isEnabled == false
              && model.trashHelp(busy).hasPrefix("Stop recording"),
              "menu enabled \(String(describing: trashItem()?.isEnabled))")
        calls.hold = true
        model.startRecording()
        await poll { recorder.transcribingID == busy }
        check("…and for the meeting that transcribes", !model.canTrash(busy) && model.trashHelp(busy).hasPrefix("Wait"))
        calls.hold = false
        await idle()
        check("…and on again once it's done", model.canTrash(busy))

        // 7. The retry cap: three failures in a row stop the launch retries; Retry starts over.
        let flaky = Meeting(info: MeetingInfo(title: "Weekly sync", start: Date().addingTimeInterval(-7_200)), notes: "")
        if let folder = try? model.library.save(flaky) {
            let dir = folder.appending(path: MeetingFolder.audio)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let writer = SegmentWriter(directory: dir, name: "mic", recordingStart: .now)
            FakeCapture.feed(writer, channels: 1, level: 0.3, seconds: 1)
            writer.finish()
            try? model.library.setTranscriptionAttempts(2, for: flaky.id)
        }
        model.reload()
        calls.failNext = true
        let first = recorder.recoverInterrupted(library: model.library)
        await idle()
        check("a failed pass counts toward the meeting's attempts and marks the meeting failed",
              first.contains(flaky.id) && model.library.transcriptionAttempts(for: flaky.id) == 3
              && recorder.failedMeetings[flaky.id] != nil,
              "queued \(first), attempts \(model.library.transcriptionAttempts(for: flaky.id))")
        recorder.dismissNotice()
        let second = recorder.recoverInterrupted(library: model.library)
        check("after three failures launch stops retrying, and the meeting stays failed with Retry",
              !second.contains(flaky.id) && recorder.failedMeetings[flaky.id]?.contains("won't run on its own") == true,
              "queued \(second), \(recorder.failedMeetings[flaky.id] ?? "none")")
        recorder.retry(flaky.id)
        await idle()
        check("Retry starts the count over and runs the pass",
              recorder.failedMeetings[flaky.id] == nil && model.library.transcriptionAttempts(for: flaky.id) == 0
              && calls.ids.last == flaky.id)

        // 8. ⌘Q while recording asks first; Cancel keeps recording, Stop and Quit closes the files.
        model.quickNote()
        let quitting = recorder.meetingID
        let cancel = recorder.terminateReply(confirm: { false })
        check("⌘Q while recording asks, and Cancel keeps recording", cancel == .terminateCancel && recorder.isRecording)
        try? await Task.sleep(for: .milliseconds(200))
        let quit = recorder.terminateReply(confirm: { true })
        let quitFiles = audioOf(quitting).flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        check("…and Stop and Quit closes the recording's files and quits",
              quit == .terminateNow && !recorder.isRecording && quitFiles.contains(Tracks.fileName),
              "\(quit.rawValue), files \(quitFiles.sorted())")
        recorder.force(.idle)
        await idle()

        // ⌘Q's question was up while the recording ended on its own: nothing is closed twice,
        // and tracks.json keeps what was written.
        model.quickNote()
        let ended = recorder.meetingID
        try? await Task.sleep(for: .milliseconds(300))
        let late = recorder.terminateReply(confirm: { recorder.stop(); return true })
        let kept = audioOf(ended).map { Tracks.load(from: $0) }
        check("a recording that ended while ⌘Q asked isn't closed again, and tracks.json keeps its audio",
              late == .terminateNow && (kept?.mic?.seconds ?? 0) > 0.3 && (kept?.system?.seconds ?? 0) > 0.3,
              "\(String(describing: kept))")
        await idle()

        // 9. The permissions sheet's Start needs only the microphone; system audio never blocks.
        let saved = (recorder.permissionsReady, recorder.micReady)
        recorder.permissionsReady = { false }
        recorder.micReady = { true }
        model.selection = nil
        model.record(.quickNote, fromSheet: true)
        check("the permissions sheet's Start records with the microphone alone",
              recorder.isRecording && model.permissionsRequest == nil)
        model.startRecording()
        await idle()
        recorder.micReady = { false }
        model.record(.quickNote, fromSheet: true)
        check("…and not without it", !recorder.isRecording && model.permissionsRequest == .quickNote)
        model.permissionsRequest = nil
        (recorder.permissionsReady, recorder.micReady) = saved
        recorder.permissionsReady = { true }
        recorder.dismissNotice()

        // The recording controls' window and the launch pass are made once per process.
        let controls = model.controls
        model.startRecordingServices()
        check("the recording controls' window is made once per process", controls != nil && model.controls === controls)
        captures()
        recorder.dismissNotice()
        for meeting in model.meetings { try? model.library.moveToTrash(meeting.id) }
        model.selection = nil
        model.reload()
    }

    /// The whole path on speech: fake captures feed `say` clips through the real writers, and
    /// the real after-call pass transcribes them (APP_SELFTEST_AUDIO=1).
    private static func checkRecordedSpeech(model: AppModel) async {
        let dir = Store.root.appending(path: "say-recorded")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func speech(_ text: String, _ name: String) -> AVAudioPCMBuffer? {
            let url = dir.appending(path: "\(name).caf")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-o", url.path, "--data-format=LEF32@16000", text]
            try? say.run()
            say.waitUntilExit()
            return readMono(url)
        }
        guard let mine = speech("Thanks everyone, I will send the revised plan tomorrow morning.", "mine"),
              let theirs = speech("Priya will share the launch checklist before the next meeting.", "theirs") else {
            check("say makes the test speech", false)
            return
        }
        let recorder = model.recorder
        let saved = (recorder.captures, recorder.permissionsReady)
        defer { (recorder.captures, recorder.permissionsReady) = saved }
        recorder.permissionsReady = { true }
        recorder.captures = CaptureFactory(mic: { FakeCapture(buffer: mine) }, system: { FakeCapture(buffer: theirs) })
        model.selection = nil
        model.startRecording()
        guard let id = recorder.meetingID else { check("the speech recording starts", false); return }
        try? await Task.sleep(for: .seconds(0.5))
        model.startRecording()
        await poll(timeout: 300) { recorder.phase == .idle || { if case .failed = recorder.phase { true } else { false } }() }
        let transcript = model.library.readTranscript(id: id)
        let me = transcript?.lines.filter { $0.side == .me }.map(\.text).joined(separator: " ").lowercased() ?? ""
        let them = transcript?.lines.filter { $0.side == .them }.map(\.text).joined(separator: " ").lowercased() ?? ""
        check("a recording made through the recorder is transcribed on both sides",
              me.contains("revised plan") && them.contains("checklist"), "phase \(recorder.phase), me \(me), them \(them)")
        try? model.library.moveToTrash(id)
        model.selection = nil
        model.reload()
    }

    /// A file's first channel at 16 kHz, or nil.
    private static func readMono(_ url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
              file.processingFormat.sampleRate == TrackFormat.sampleRate,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil else { return nil }
        return buffer
    }

    /// Clips placed at times in seconds on one silent 16 kHz mono buffer, with a second of
    /// silence after the last.
    private static func timeline(_ clips: [(TimeInterval, AVAudioPCMBuffer)]) -> AVAudioPCMBuffer {
        let rate = TrackFormat.sampleRate
        let frames = clips.map { Int($0.0 * rate) + Int($0.1.frameLength) }.max().map { $0 + Int(rate) } ?? 0
        let out = AVAudioPCMBuffer(pcmFormat: TrackFormat.format, frameCapacity: AVAudioFrameCount(frames))!
        out.frameLength = AVAudioFrameCount(frames)
        let dst = out.floatChannelData![0]
        for i in 0..<frames { dst[i] = 0 }
        for (at, clip) in clips {
            guard let src = clip.floatChannelData?[0] else { continue }
            let start = Int(at * rate)
            for i in 0..<Int(clip.frameLength) where start + i < frames { dst[start + i] = src[i] }
        }
        return out
    }

    /// Feeds a buffer to a writer in 1-second pieces, as a device would, and closes it.
    private static func write(_ buffer: AVAudioPCMBuffer, to writer: SegmentWriter) {
        let step = Int(TrackFormat.sampleRate)
        var at = 0
        while at < Int(buffer.frameLength) {
            let n = min(step, Int(buffer.frameLength) - at)
            guard let piece = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(n)) else { break }
            piece.frameLength = AVAudioFrameCount(n)
            memcpy(piece.floatChannelData![0], buffer.floatChannelData![0] + at, n * MemoryLayout<Float>.size)
            writer.append(piece)
            at += n
        }
        writer.finish()
    }

    /// The menu bar item's titles, as its menu lists them now.
    private static func menuBarTitles(model: AppModel) -> [String] {
        MenuBarMenu.entries(model: model).compactMap { entry in
            switch entry {
            case let .text(title), let .button(title, _): title
            case .divider: nil
            }
        }
    }

    private static func menuItem(title: String, in menu: NSMenu?) -> NSMenuItem? {
        for item in menu?.items ?? [] {
            if item.title == title { return item }
            if let found = menuItem(title: title, in: item.submenu) { return found }
        }
        return nil
    }

    /// Waits until `condition` holds, checking every 50 ms, for at most `timeout` seconds.
    /// The check that follows reports what it finds either way.
    private static func poll(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { try? await Task.sleep(for: .milliseconds(50)) }
    }

    /// Which header click target AppKit hits at a point measured from the window's top left:
    /// "sidebar", "canvas", or "other" (a control drawn over them, or anything else).
    private static func headerArea(at point: CGPoint, in window: NSWindow) -> String {
        guard let content = window.contentView, let frame = content.superview else { return "no content view" }
        let inFrame = frame.convert(NSPoint(x: point.x, y: window.frame.height - point.y), from: nil)
        guard let hit = content.hitTest(inFrame) else { return "nothing" }
        return (hit as? HeaderClickView.ClickView)?.area.rawValue ?? "other"
    }

    private static func menuItem(key: String, modifiers: NSEvent.ModifierFlags, in menu: NSMenu?) -> NSMenuItem? {
        for item in menu?.items ?? [] {
            if item.keyEquivalent == key, item.keyEquivalentModifierMask == modifiers { return item }
            if let found = menuItem(key: key, modifiers: modifiers, in: item.submenu) { return found }
        }
        return nil
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

/// What the self-test's stand-in after-call pass was asked to do.
private final class AfterCallCalls {
    var ids: [String] = []
    var stitched: [String: [String]] = [:]
    var failNext = false
    /// While true, the pass waits (to check a meeting that transcribes).
    var hold = false
}

/// A capture that opens no device: it feeds a made-up tone (or a given buffer) to the real
/// SegmentWriter, half a second at once and then 0.1 s every 0.1 s until stopped, at 48 kHz
/// in the given channels, as a device might. Modes act out what goes wrong live.
nonisolated final class FakeCapture: AudioCapture, @unchecked Sendable {
    enum Mode {
        case tone
        /// Starts, then never delivers a buffer.
        case silent
        /// Throws from start, as a microphone that won't open.
        case failsToStart
        /// Its writer fails after a few buffers, as a disk that fills.
        case failsWriting
        /// The device changes after a few buffers: a new segment at 44.1 kHz, as MicCapture does.
        case changesDevice
        /// Starts once, then throws on every later start (Resume after Pause).
        case failsOnRestart
    }

    private let channels: AVAudioChannelCount
    private let level: Float
    private let buffer: AVAudioPCMBuffer?
    private let mode: Mode
    /// Seconds per buffer after the first half second: devices differ (a microphone near
    /// 85 ms, call audio near 10 ms).
    private let chunk: Double
    /// Audio delivered at once on start, ahead of the clock (a real device delivers none).
    private let burst: Double
    private var timer: DispatchSourceTimer?
    private(set) var starts = 0
    var isRunning: Bool { timer != nil }

    init(channels: AVAudioChannelCount, level: Float, mode: Mode = .tone, chunk: Double = 0.1, burst: Double = 0.5) {
        self.channels = channels
        self.level = level
        buffer = nil
        self.mode = mode
        self.chunk = chunk
        self.burst = burst
    }

    /// Feeds a whole buffer (16 kHz mono speech) at once, then nothing.
    init(buffer: AVAudioPCMBuffer) {
        channels = 1
        level = 0
        self.buffer = buffer
        mode = .tone
        chunk = 0.1
        burst = 0.5
    }

    func start(into writer: SegmentWriter) throws {
        if mode == .failsToStart || (mode == .failsOnRestart && starts > 0) { throw CocoaError(.featureUnsupported) }
        starts += 1
        if mode == .silent { return }
        if let buffer {
            writer.append(buffer)
            return
        }
        if burst > 0 { Self.feed(writer, channels: channels, level: level, seconds: burst) }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "silvanus.fake-capture"))
        timer.schedule(deadline: .now() + chunk, repeating: chunk)
        final class Clock: @unchecked Sendable {
            var ticks = 0
            var rate = 48_000.0
        }
        let clock = Clock()
        timer.setEventHandler { [channels, level, mode, chunk] in
            clock.ticks += 1
            if clock.ticks == 3, mode == .failsWriting { writer.recordFailure("Couldn't write audio: The test disk is full.") }
            if clock.ticks == 3, mode == .changesDevice {
                writer.breakSegment()
                clock.rate = 44_100
            }
            Self.feed(writer, channels: channels, level: level, seconds: chunk, rate: clock.rate)
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// A 440 Hz tone at `level`, in every channel, appended to the writer.
    static func feed(_ writer: SegmentWriter, channels: AVAudioChannelCount, level: Float, seconds: Double,
                     rate: Double = 48_000) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels),
              let tone = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * rate)) else { return }
        tone.frameLength = tone.frameCapacity
        for channel in 0..<Int(channels) {
            guard let data = tone.floatChannelData?[channel] else { continue }
            for i in 0..<Int(tone.frameLength) { data[i] = level * sin(2 * .pi * 440 * Float(i) / Float(rate)) }
        }
        writer.append(tone)
    }
}

/// An audio engine that opens no device, for MicCapture's checks: it counts taps and
/// starts, and its input can be made to vanish (a Bluetooth switch).
nonisolated final class FakeMicEngine: MicEngine, @unchecked Sendable {
    let notificationObject: AnyObject = NSObject()
    private let lock = NSLock()
    private var _formatAvailable = true
    private var _taps = 0, _maxTaps = 0, _installs = 0, _running = false
    /// How long start takes, to widen races.
    var startDelay: TimeInterval = 0

    var formatAvailable: Bool {
        get { lock.withLock { _formatAvailable } }
        set { lock.withLock { _formatAvailable = newValue } }
    }
    var taps: Int { lock.withLock { _taps } }
    var maxTaps: Int { lock.withLock { _maxTaps } }
    var installs: Int { lock.withLock { _installs } }
    var running: Bool { lock.withLock { _running } }

    func inputFormat() -> AVAudioFormat? {
        formatAvailable ? AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1) : nil
    }

    func installTap(format: AVAudioFormat, block: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        lock.withLock {
            _taps += 1
            _installs += 1
            _maxTaps = max(_maxTaps, _taps)
        }
    }

    func removeTap() { lock.withLock { _taps = max(0, _taps - 1) } }

    func start() throws {
        if startDelay > 0 { Thread.sleep(forTimeInterval: startDelay) }
        lock.withLock { _running = true }
    }

    func stop() { lock.withLock { _running = false } }
}

/// The downloader's events, collected from whatever thread sends them.
private nonisolated final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [ModelDownloader.Event] = []
    var events: [ModelDownloader.Event] { lock.withLock { seen } }
    func add(_ event: ModelDownloader.Event) { lock.withLock { seen.append(event) } }
}
