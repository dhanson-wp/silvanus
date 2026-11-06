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
            await checkNotesAcrossViews(model: model)
            await checkTranscript(model: model)
            await checkPlayback()
            await checkSummary(model: model)
            checkAudio()
            await checkMicRestarts()
            await checkMeetingDetection(model: model)
            await checkRecording(model: model)
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
        let since = recorder.since
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

        // The pill: hidden while the main window is key, shown when another window is.
        // A run started from a terminal may never be the active app, so the main window's
        // key state is given here; the panel reads the real one otherwise.
        let panel = RecordingPanel(recorder: recorder, model: model)
        panel.mainWindowIsKey = { true }
        panel.update()
        let hiddenWhenKey = !panel.isShowing
        panel.mainWindowIsKey = { false }
        panel.update()
        let shownElsewhere = panel.isShowing
        let floating = NSApp.windows.contains { $0 is NSPanel && $0.isVisible && $0.level == .floating }
        panel.mainWindowIsKey = { true }
        panel.update()
        check("the recording pill shows, floating, only when the main window isn't key",
              hiddenWhenKey && shownElsewhere && floating && !panel.isShowing,
              "hidden while key \(hiddenWhenKey), shown elsewhere \(shownElsewhere), floating \(floating), showing after \(panel.isShowing)")

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

    /// The call detector with a fake probe: "Meeting detected" once per call, never with no
    /// call app, never while recording, not when the setting is off, and gone after its time.
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
        detector.poll()
        check("a call app using the microphone shows \"Meeting detected\"", prompt.isShowing && prompt.shown == shown + 1)
        detector.poll()
        detector.poll()
        check("…once per call", prompt.shown == shown + 1, "shown \(prompt.shown - shown)")
        check("…and the recorder hears that a call app runs", model.recorder.callAppRunning)
        prompt.hide()
        release()
        model.promptOnMeeting = false
        check("turning the prompt off is saved", AppDefaults.shared.object(forKey: AppDefaults.promptOnMeetingKey) as? Bool == false)
        fake.mic = true
        detector.poll()
        check("with Prompt when a meeting starts off, nothing shows", !prompt.isShowing && prompt.shown == shown + 1)
        model.promptOnMeeting = true
        release()
        model.recorder.force(.recording(since: Date()))
        fake.mic = true
        detector.poll()
        check("nothing shows while Silvanus records", !prompt.isShowing && prompt.shown == shown + 1)
        model.recorder.force(.idle)
        detector.poll()
        check("…nor after it stops mid-call", !prompt.isShowing && prompt.shown == shown + 1)
        release()
        prompt.seconds = 0.3
        fake.mic = true
        detector.poll()
        let up = prompt.isShowing
        await poll { !prompt.isShowing }
        check("the prompt hides itself after its time", up && !prompt.isShowing)
        prompt.seconds = Metric.meetingPromptSeconds
        prompt.hide()
        // A browser open but not using input (an in-person meeting): no call.
        let chromeOpen = CallDetector.Probe(callAppsUsingInput: { [] }, micInUseElsewhere: { true },
                                            runningCallApps: { ["com.google.Chrome"] })
        check("a call app that's open but not using input isn't a call",
              !chromeOpen.callInProgress(recording: false) && !chromeOpen.callInProgress(recording: true))
        let noList = CallDetector.Probe(callAppsUsingInput: { nil }, micInUseElsewhere: { true },
                                        runningCallApps: { ["us.zoom.xos"] })
        check("without the process list, the input device running while a call app runs is a call",
              noList.callInProgress(recording: false))
        let live = CallDetector.liveCallAppsUsingInput()
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
    /// fails mid-call, call audio that fails, a microphone that changes or goes quiet, Stop
    /// before any audio, Move to Trash while busy, the retry cap, ⌘Q while recording, and the
    /// permissions sheet's Start.
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

        // 2. The microphone's writer fails mid-call: the pill keeps the reason until closed, and
        // what was saved is transcribed.
        captures(mic: .failsWriting)
        model.quickNote()
        let broken = recorder.meetingID
        await poll { recorder.recordingFailure != nil }
        let panel = RecordingPanel(recorder: recorder, model: model)
        panel.mainWindowIsKey = { false }
        panel.update()
        let pillUp = panel.isShowing
        check("a microphone that fails stops the recording with \"Couldn't write audio: …\"",
              recorder.recordingFailure?.hasPrefix("Couldn't write audio:") == true && !recorder.isRecording,
              "failure \(recorder.recordingFailure ?? "none"), phase \(recorder.phase)")
        await idle()
        check("…the audio saved before it is transcribed on its own", calls.ids.last == broken && broken != nil,
              "calls \(calls.ids.suffix(1))")
        check("…and the pill stays up with the reason until it's closed", pillUp && recorder.recordingFailure != nil)
        recorder.dismissNotice()
        panel.update()
        check("closing it clears the failure and hides the pill",
              recorder.recordingFailure == nil && recorder.notice == nil && !panel.isShowing)

        // 3. Call audio fails mid-call: the microphone records on.
        captures(system: .failsWriting)
        model.quickNote()
        let micOnly = recorder.meetingID
        await poll { recorder.warning?.hasPrefix(Recorder.micOnly) == true }
        check("call audio that fails drops to the microphone alone and keeps recording",
              recorder.isRecording && recorder.warning?.hasPrefix(Recorder.micOnly) == true,
              "recording \(recorder.isRecording), warning \(recorder.warning ?? "none")")
        try? await Task.sleep(for: .milliseconds(300))
        model.startRecording()
        let micOnlyTracks = audioOf(micOnly).map { Tracks.load(from: $0) }
        check("…and tracks.json keeps both sides, the call audio up to where it stopped",
              (micOnlyTracks?.mic?.seconds ?? 0) > (micOnlyTracks?.system?.seconds ?? 0) && (micOnlyTracks?.system?.seconds ?? 0) > 0,
              "\(String(describing: micOnlyTracks))")
        await idle()

        // 4. The microphone changes mid-call: a new segment in the same track. A quiet microphone warns.
        captures(mic: .changesDevice)
        model.quickNote()
        let changed = recorder.meetingID
        try? await Task.sleep(for: .milliseconds(700))
        model.startRecording()
        let micSegments = audioOf(changed).map { SegmentWriter.segments(named: "mic", in: $0).count } ?? 0
        let micSeconds = audioOf(changed).map { Tracks.load(from: $0) }?.mic?.seconds ?? 0
        check("a microphone that changes goes on in a new segment of the same track",
              micSegments >= 2 && micSeconds > 0.9, "segments \(micSegments), seconds \(micSeconds)")
        await idle()
        recorder.silenceWarning = 0.3
        captures(mic: .silent)
        model.quickNote()
        await poll { recorder.warning?.contains(Recorder.silentMic) == true }
        check("a microphone that stays silent shows a warning", recorder.warning?.contains(Recorder.silentMic) == true,
              recorder.warning ?? "none")
        recorder.silenceWarning = 30

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

        // 5b. Call audio that stays silent warns only during a call, never for Quick Note.
        recorder.silenceWarning = 0.3
        captures(system: .silent)
        recorder.callAppProbe = { true }
        model.quickNote()
        try? await Task.sleep(for: .milliseconds(800))
        check("Quick Note never warns about call audio, even with a call app open",
              recorder.isRecording && recorder.warning?.contains(Recorder.silentCall) != true, recorder.warning ?? "none")
        model.startRecording()
        await idle()
        model.startRecording()
        await poll { recorder.warning?.contains(Recorder.silentCall) == true }
        check("during a call, silent call audio says \"Nobody on the call is audible yet. Check System Audio access in Settings.\"",
              recorder.warning?.contains("Nobody on the call is audible yet. Check System Audio access in Settings.") == true,
              recorder.warning ?? "none")
        check("…and the microphone warning isn't mixed in while the microphone is heard",
              recorder.warning?.contains(Recorder.silentMic) != true, recorder.warning ?? "none")
        model.startRecording()
        await idle()
        recorder.callAppProbe = { false }
        model.startRecording()
        try? await Task.sleep(for: .milliseconds(800))
        check("with no call app at the start or since, silent call audio never warns",
              recorder.isRecording && recorder.warning?.contains(Recorder.silentCall) != true, recorder.warning ?? "none")
        model.startRecording()
        await idle()
        recorder.silenceWarning = 30

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

        // The pill's window and the launch pass are made once per process.
        let pill = model.pill
        model.startRecordingServices()
        check("the recording pill's window is made once per process", pill != nil && model.pill === pill)
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
    }

    private let channels: AVAudioChannelCount
    private let level: Float
    private let buffer: AVAudioPCMBuffer?
    private let mode: Mode
    private var timer: DispatchSourceTimer?

    init(channels: AVAudioChannelCount, level: Float, mode: Mode = .tone) {
        self.channels = channels
        self.level = level
        buffer = nil
        self.mode = mode
    }

    /// Feeds a whole buffer (16 kHz mono speech) at once, then nothing.
    init(buffer: AVAudioPCMBuffer) {
        channels = 1
        level = 0
        self.buffer = buffer
        mode = .tone
    }

    func start(into writer: SegmentWriter) throws {
        if mode == .failsToStart { throw CocoaError(.featureUnsupported) }
        if mode == .silent { return }
        if let buffer {
            writer.append(buffer)
            return
        }
        Self.feed(writer, channels: channels, level: level, seconds: 0.5)
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "silvanus.fake-capture"))
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        final class Clock: @unchecked Sendable {
            var ticks = 0
            var rate = 48_000.0
        }
        let clock = Clock()
        timer.setEventHandler { [channels, level, mode] in
            clock.ticks += 1
            if clock.ticks == 3, mode == .failsWriting { writer.recordFailure("Couldn't write audio: The test disk is full.") }
            if clock.ticks == 3, mode == .changesDevice {
                writer.breakSegment()
                clock.rate = 44_100
            }
            Self.feed(writer, channels: channels, level: level, seconds: 0.1, rate: clock.rate)
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
