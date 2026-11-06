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
            try? model.library.moveToTrash(meeting.id)
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
        try? await Task.sleep(for: .seconds(0.5))
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
        NSApp.mainMenu?.update()
        menu.delegate?.menuNeedsUpdate?(menu)
        try? await Task.sleep(for: .seconds(0.3))
        let hidden = !model.sidebarVisible
        let showTitle = menuItem(key: "s", modifiers: [.control, .command], in: NSApp.mainMenu)?.title
        check("⌃⌘S hides the sidebar and the item turns to Show Sidebar", hidden && showTitle == "Show Sidebar",
              "visible \(model.sidebarVisible), title \(showTitle ?? "missing")")
        if let again = menuItem(key: "s", modifiers: [.control, .command], in: NSApp.mainMenu), let menu = again.menu {
            menu.performActionForItem(at: menu.index(of: again))
        }
        try? await Task.sleep(for: .seconds(0.3))
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
            check("File has \(title), disabled until recording is wired in",
                  item?.title == title && item?.isEnabled == false && !model.canRecord, item?.title ?? "missing")
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
