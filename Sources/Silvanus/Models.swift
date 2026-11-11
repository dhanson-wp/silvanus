import Foundation
import SilvanusKit
import SwiftUI
import UniformTypeIdentifiers

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case all, starred

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Meetings"
        case .starred: "Starred"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray"
        case .starred: "star"
        }
    }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    init(library: MeetingLibrary) {
        self.library = library
        recorder = Recorder(library: library)
        appearance.apply()
        recorder.model = self
        refreshCalendar()
    }

    let library: MeetingLibrary
    /// Recording and the after-call pass (Recorder.swift).
    let recorder: Recorder
    /// The recording controls' window, made once per process.
    @ObservationIgnored private(set) var controls: RecordingPanel?
    /// Notices a meeting starting (CallDetector.swift), made once per process.
    @ObservationIgnored private(set) var detector: CallDetector?
    /// The "Meeting detected" prompt's window.
    @ObservationIgnored private(set) var meetingPrompt: MeetingPromptPanel?
    /// A call the detector noticed while Silvanus wasn't recording, until it ends or a
    /// recording starts. The menu bar's Record Meeting stays while it waits, so the prompt's
    /// offer is still there after Not now.
    var detectedCall: DetectedCall?
    /// Every meeting on disk, newest first. Setting it rebuilds the sidebar's folders and days.
    var meetings: [Meeting] = [] {
        didSet {
            folders = SidebarFolders.list(meetings)
            // A folder that no longer holds a meeting is gone from the sidebar, so stop showing it.
            if let folder, !folders.contains(where: { $0.name == folder }) {
                self.folder = nil
            } else {
                regroup()
            }
        }
    }
    /// Folders that hold no readable meeting.json.
    var unreadable: [URL] = []
    var sidebar: SidebarItem? = .all
    /// The selected meeting's id. A header request waiting for the old meeting is dropped.
    var selection: String? {
        didSet {
            if selection != oldValue {
                if selection != nil { showingTodos = false }
                headerRequest = nil
                selectionChanged?(selection)
            }
        }
    }
    /// Called after the selection changes (the notes canvas closes the old meeting's notes).
    @ObservationIgnored var selectionChanged: ((String?) -> Void)?
    /// Called with a meeting's id just before it's trashed, so the notes canvas can save
    /// typing still in it first.
    @ObservationIgnored var beforeTrash: ((String) -> Void)?
    /// The sidebar folder the meeting list shows; nil is All meetings.
    var folder: String? {
        didSet { if folder != oldValue { regroup() } }
    }
    /// When the sidebar last looked at the clock. The sidebar moves it at each midnight, and
    /// the days regroup only when the day changed.
    var now = Date() {
        didSet {
            if !Calendar.current.isDate(now, inSameDayAs: oldValue) { regroup() }
        }
    }
    /// The sidebar's folders, sorted, with their meeting counts. Rebuilt with `meetings`.
    private(set) var folders: [(name: String, count: Int)] = []
    /// The meetings the sidebar lists (the chosen folder's, or every one), grouped by day.
    /// Rebuilt only when the meetings, the folder, or the day change, never on a selection
    /// change, so arrow keys stay fast with hundreds of meetings.
    private(set) var visibleMeetings: [Meeting] = []
    private(set) var dayGroups: [DayGroup] = []
    /// The listed meetings' ids in sidebar order, for the arrow keys.
    private(set) var sidebarOrder: [String] = []
    /// How many times the days were rebuilt. The self-test reads it.
    @ObservationIgnored private(set) var regroupCount = 0
    /// True only for the reference-main snapshot (Snapshot.captureReferenceMain): My notes
    /// shows the editor without the meeting header, and the sidebar leaves out Folders, so
    /// the window has the same parts as the reference capture design/KIT.md was measured from.
    var referenceStage = false
    /// False when the sidebar is hidden (View > Hide Sidebar, ⌃⌘S, or the header button).
    var sidebarVisible = true
    /// What the canvas shows for the open meeting (the view pill, ⌘1, ⌘2, ⌘3). Leaving My
    /// notes saves the typing first, while the editor is still on screen.
    var canvasMode: CanvasMode = .notes {
        willSet { if newValue != canvasMode, canvasMode == .notes { leavingNotes?() } }
    }
    /// Where the transcript last asked to play from. The snapshot and self-test read it.
    @ObservationIgnored var lastSeek: TimeInterval?
    /// True while a meeting records.
    var isRecording: Bool { recorder.isRecording }
    /// Start Recording and Quick Note are always on: a missing permission opens the
    /// permissions sheet instead of failing.
    let canRecord = true
    /// The permissions sheet, shown by a Start Recording or Quick Note that needs
    /// Microphone access or System audio access first. Never shown at launch.
    var permissionsRequest: RecordRequest?
    /// A Meeting menu item waiting for the meeting header (Rename Meeting…, Show Attendees,
    /// Move to Folder > New Folder…). It stays until the header acts on it, so a request made
    /// from Transcript, where the header isn't on screen, lands once the header appears.
    var headerRequest: HeaderRequest?
    /// How many requests the header has carried out. The self-test reads it.
    @ObservationIgnored private(set) var handledHeaderRequests: [HeaderRequest] = []
    /// True while Settings takes the window (⌘, or the app menu's Settings…). Opening it saves
    /// the notes' typing first, while the editor is still on screen.
    var settingsOpen = false {
        willSet { if newValue, !settingsOpen { leavingNotes?() } }
    }
    /// Saves the open notes now (the notes canvas sets it). Called before My notes leaves
    /// the canvas.
    @ObservationIgnored var leavingNotes: (() -> Void)?
    /// Every meeting Move to Trash was asked for (menu or sidebar). The self-test reads it.
    @ObservationIgnored private(set) var trashRequests: [String] = []
    /// Settings reopens on the last pane. Test and snapshot runs use their own defaults.
    var settingsPane: SettingsPane = SettingsPane(rawValue: AppDefaults.shared.string(forKey: AppDefaults.settingsPaneKey) ?? "") ?? .general {
        didSet { AppDefaults.shared.set(settingsPane.rawValue, forKey: AppDefaults.settingsPaneKey) }
    }
    /// Settings > Appearance. Setting it saves it and applies it to every window.
    var appearance: AppearanceChoice = AppDefaults.appearance {
        didSet {
            AppDefaults.appearance = appearance
            appearance.apply()
        }
    }
    /// Settings > Summaries > Model: the chosen file's path. Nil uses a model another app downloaded.
    var summaryModelPath: String? = AppDefaults.shared.string(forKey: AppDefaults.modelFileKey) {
        didSet { AppDefaults.shared.set(summaryModelPath, forKey: AppDefaults.modelFileKey) }
    }
    /// The model file that writes to-dos and summaries, or nil when there's none.
    /// Snapshots show a made-up one, so they don't depend on what's on this Mac.
    var summaryModel: LocalModelFile.Found? {
        if Snapshot.requested {
            return LocalModelFile.Found(url: URL(fileURLWithPath: "/gemma-4-12b-it.gguf"), source: .shared("Biscotti"))
        }
        return LocalModelFile.find(chosen: summaryModelPath, home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Settings > Summaries > Choose…: pick a GGUF model file.
    func chooseSummaryModel() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Model File"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [UTType(filenameExtension: "gguf") ?? .data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let current = summaryModel?.url { panel.directoryURL = current.deletingLastPathComponent() }
        guard panel.runModal() == .OK, let url = panel.url, LocalModelFile.isModel(url) else { return }
        summaryModelPath = url.path
    }

    // MARK: - Calendar

    /// Where events come from: the Mac's calendars, or made-up events in test runs.
    @ObservationIgnored var calendar: CalendarSource = AppDefaults.isTest ? .fixed([], access: .notAsked) : .live {
        didSet { refreshCalendar() }
    }
    /// Whether Silvanus may read the calendar. Home and Settings > Calendar show it.
    private(set) var calendarAccess: CalendarAccess = .notAsked
    /// Events from yesterday to two weeks ahead, read when access is allowed.
    private(set) var calendarEvents: [CalendarEvent] = []
    /// The accounts whose calendars the Mac has ("Google", "iCloud"). Settings > Calendar lists them.
    private(set) var calendarAccounts: [String] = []
    @ObservationIgnored private var watchingCalendar = false

    /// Today and tomorrow for the home page's Coming up card.
    var comingUp: [CalendarRules.Day] { CalendarRules.comingUp(calendarEvents, now: now) }

    /// Reads the events again. Cheap; called at launch, when Home shows, when the calendars
    /// change, and when a recording starts.
    func refreshCalendar(now: Date = Date()) {
        calendarAccess = calendar.access()
        guard calendarAccess == .allowed else {
            calendarEvents = []
            calendarAccounts = []
            return
        }
        calendarAccounts = calendar.accounts()
        calendarEvents = calendar.events(now.addingTimeInterval(-86_400), now.addingTimeInterval(14 * 86_400))
        if !watchingCalendar {
            watchingCalendar = true
            calendar.onChange { [weak self] in self?.refreshCalendar() }
        }
    }

    /// Connect Calendar (Home, Settings > Calendar): asks macOS once, then reads the events.
    func connectCalendar() {
        Task {
            _ = await calendar.request()
            refreshCalendar()
        }
    }

    /// Add Google Calendar: opens System Settings > Internet Accounts, where a Google account
    /// is added with Calendars on. Its events then show up here on their own.
    func addCalendarAccount() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open System Settings… when calendar access was turned down.
    func openCalendarSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The calendar event a recording starting at `date` belongs to, if any.
    func calendarEvent(at date: Date) -> CalendarEvent? {
        refreshCalendar(now: date)
        return CalendarRules.event(at: date, in: calendarEvents)
    }

    /// A Coming up event was clicked: open its meeting, making it (titled after the event,
    /// with its attendees) the first time.
    func open(event: CalendarEvent) {
        if let made = CalendarRules.meeting(for: event, in: meetings) {
            open(made.id)
        } else {
            // An event that's on starts now; one still ahead keeps its own start.
            newMeeting(now: max(event.start, Date()),
                       title: event.title.isEmpty ? Meeting.untitled : event.title, attendees: event.attendees)
        }
    }

    /// Join: opens the event's call link, if it's on a call service's own domain.
    func join(_ event: CalendarEvent) {
        guard let link = event.link, CalendarRules.isCallLink(link) else { return }
        NSWorkspace.shared.open(link)
    }

    // MARK: - To-dos

    /// What's happening to a meeting's to-do list.
    enum TodoStatus: Equatable {
        case writing
        case failed(String)
    }

    static let writingTodos = "Writing to-dos…"
    static func todoFailure(_ reason: String) -> String { "Couldn't write to-dos: \(reason)" }

    /// Asks the model that writes to-dos: the local one. The self-test swaps in its own.
    @ObservationIgnored var askModel: TodoWriter.Ask = {
        try await LocalModel.ask(system: $0, user: $1)
    }
    /// Meetings whose to-do list is being written, or couldn't be.
    private(set) var todoStatus: [String: TodoStatus] = [:]
    /// Goes up each time a to-do list is written, so the Summary page reads it again.
    private(set) var todoRevision = 0
    /// One list at a time: the model is large.
    @ObservationIgnored private var todoWork: Task<Void, Never>?

    /// True when Meeting > Write To-dos can run: the meeting has a transcript and isn't being written.
    func canWriteTodos(_ id: String?) -> Bool {
        guard let id, let meeting = meetings.first(where: { $0.id == id }) else { return false }
        return !meeting.transcriptMarkdown.isEmpty && todoStatus[id] != .writing
    }

    /// Writes the meeting's to-dos from its transcript with the local model, keeping what
    /// the user changed (`Todos.merge`). `asked` is true from the menu: then a missing model
    /// is reported; after a call it's skipped quietly.
    @discardableResult
    func writeTodos(for id: String, asked: Bool) -> Task<Void, Never>? {
        guard todoStatus[id] != .writing else { return todoWork }
        if !asked, !todoModelIsInjected, LocalModel.file() == nil { return nil }
        todoStatus[id] = .writing
        let earlier = todoWork
        let work = Task { [weak self] in
            await earlier?.value
            guard let self else { return }
            do {
                if let saved = try await TodoWriter.write(id: id, library: library, me: AppDefaults.meName, ask: askModel) {
                    todoSaved(saved, for: id)
                }
                todoStatus[id] = nil
            } catch {
                print("TODOS \(id): \(error.localizedDescription)")
                todoStatus[id] = .failed(error.localizedDescription)
            }
            todoRevision += 1
        }
        todoWork = work
        return work
    }

    // MARK: - Summary

    static let writingSummary = "Writing the summary…"
    static func summaryFailure(_ reason: String) -> String { "Couldn't write the summary: \(reason)" }

    /// Meetings whose summary is being written, or couldn't be.
    private(set) var summaryStatus: [String: TodoStatus] = [:]

    /// True when Meeting > Write Summary can run: the meeting has a transcript and isn't being written.
    func canWriteSummary(_ id: String?) -> Bool {
        guard let id, let meeting = meetings.first(where: { $0.id == id }) else { return false }
        return !meeting.transcriptMarkdown.isEmpty && summaryStatus[id] != .writing
    }

    /// Writes the meeting's summary from its transcript with the local model, above
    /// anything already in `summary.md` (`Summaries.merge`). `asked` as for `writeTodos`.
    @discardableResult
    func writeSummary(for id: String, asked: Bool) -> Task<Void, Never>? {
        guard summaryStatus[id] != .writing else { return todoWork }
        if !asked, !todoModelIsInjected, LocalModel.file() == nil { return nil }
        summaryStatus[id] = .writing
        let earlier = todoWork
        let work = Task { [weak self] in
            await earlier?.value
            guard let self else { return }
            do {
                if let saved = try await SummaryWriter.write(id: id, library: library, me: AppDefaults.meName, ask: askModel),
                   let index = meetings.firstIndex(where: { $0.id == id }) {
                    meetings[index].summary = saved
                }
                summaryStatus[id] = nil
            } catch {
                print("SUMMARY \(id): \(error.localizedDescription)")
                summaryStatus[id] = .failed(error.localizedDescription)
            }
            todoRevision += 1
        }
        todoWork = work
        return work
    }

    /// True when the self-test's model stands in for the file, so a run without one still writes.
    @ObservationIgnored var todoModelIsInjected = false

    /// True while the canvas shows the To-dos page (the sidebar's To-dos row, ⇧⌘T) in place
    /// of the open meeting. Opening a meeting leaves it.
    var showingTodos = false {
        willSet { if newValue, !showingTodos { leavingNotes?() } }
    }

    /// To-dos that belong to no meeting (`<root>/todo.md`), added on the To-dos page.
    private(set) var ownTodo = ""

    /// Open to-dos, mine and every meeting's: the count on the sidebar's To-dos row.
    var openTodoCount: Int {
        TodoBoard.openCount(meetings) + TodoBoard.items(in: ownTodo, meetingID: TodoBoard.own).count { !$0.done }
    }

    /// True while the canvas shows the home page: no meeting open, and not To-dos.
    var isHome: Bool { selection == nil && !showingTodos }

    /// Home (the sidebar's Home row, ⇧⌘H): closes the open meeting and shows what's coming up.
    func showHome() {
        refreshCalendar()
        settingsOpen = false
        showingTodos = false
        selection = nil
    }

    func showTodos() {
        settingsOpen = false
        showingTodos = true
    }

    /// Ticks or unticks a to-do from the To-dos page.
    func toggleTodo(_ item: TodoBoard.Item) {
        changeTodos(item.meetingID) { TodoBoard.toggled($0, line: item.line) }
    }

    /// Changes a to-do's words from the To-dos page; blank words remove it.
    func editTodo(_ item: TodoBoard.Item, text: String) {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines) != item.text else { return }
        changeTodos(item.meetingID) { TodoBoard.edited($0, line: item.line, text: text) }
    }

    func deleteTodo(_ item: TodoBoard.Item) {
        changeTodos(item.meetingID) { TodoBoard.removed($0, line: item.line) }
    }

    /// Adds an open to-do to a meeting's list, or to mine (`TodoBoard.own`).
    func addTodo(_ text: String, to list: String) {
        changeTodos(list) { TodoBoard.added($0, text: text) }
    }

    /// Meeting > New To-do: starts or extends the open meeting's list with a to-do to type
    /// over, and shows it on Summary with its words selected.
    static let newTodoText = "New to-do"
    /// The meeting whose newest to-do the Summary page should select. The page clears it.
    var todoToSelect: String?

    func newTodo(in id: String) {
        addTodo(Self.newTodoText, to: id)
        todoToSelect = id
        open(id)
        show(.summary)
    }

    /// Reads a list as it is on disk, changes it, and saves it. Nothing is written when
    /// `change` returns nil or the same text.
    private func changeTodos(_ list: String, _ change: (String) -> String?) {
        let own = list == TodoBoard.own
        let current = own ? library.readOwnTodo() : (library.readTodo(id: list) ?? "")
        guard let changed = change(current), changed != current else { return }
        do {
            if own {
                try library.saveOwnTodo(changed)
                ownTodo = changed
            } else {
                try library.saveTodo(changed, for: list)
                todoSaved(changed, for: list)
            }
            todoRevision += 1
        } catch {
            print("TODOS couldn't save \(own ? "my to-dos" : list): \(error.localizedDescription)")
        }
    }

    /// The Summary page saved the to-do list: keep the loaded copy current.
    func todoSaved(_ text: String, for id: String) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        meetings[index].todo = text
    }

    /// Settings > General > Show in Dock. Saved only; no behavior yet.
    var showInDock: Bool = AppDefaults.showInDock {
        didSet { AppDefaults.showInDock = showInDock }
    }
    /// Settings > General > Prompt when a meeting starts. Turning it off hides a prompt
    /// that's up.
    var promptOnMeeting: Bool = AppDefaults.promptOnMeeting {
        didSet {
            AppDefaults.promptOnMeeting = promptOnMeeting
            if !promptOnMeeting {
                meetingPrompt?.hide()
                detectedCall = nil
            }
        }
    }
    /// Settings > General > Stop when the call ends. The recorder reads the saved value at
    /// each step, so turning it off cancels a countdown that's running.
    var stopWhenCallEnds: Bool = AppDefaults.stopWhenCallEnds {
        didSet { AppDefaults.stopWhenCallEnds = stopWhenCallEnds }
    }
}

extension AppModel {
    @ObservationIgnored private static var servicesStarted = false

    /// Once per process, when the app's model is made: the recording controls' window, and the
    /// launch pass that finishes recordings cut off by a quit or crash (not in checks or
    /// snapshots, which drive the recorder themselves).
    func startRecordingServices() {
        guard !Self.servicesStarted else { return }
        Self.servicesStarted = true
        controls = RecordingPanel(recorder: recorder, model: self)
        meetingPrompt = MeetingPromptPanel(model: self)
        detector = makeDetector()
        if !SelfTest.requested && !Snapshot.requested {
            recorder.recoverInterrupted(library: library)
            // Checks and snapshots drive their own detector with a fake probe.
            detector?.start()
        }
    }

    /// A call detector wired to this model: a meeting start shows the prompt (and the menu
    /// bar's Record Meeting), the call's end takes both away, and each poll tells the
    /// recorder whether a call app is using the microphone.
    func makeDetector(probe: CallDetector.Probe = .live) -> CallDetector {
        let detector = CallDetector(probe: probe, isRecording: { [weak self] in self?.recorder.isRecording ?? false },
                                    isEnabled: { [weak self] in self?.promptOnMeeting ?? false })
        detector.meetingStarted = { [weak self] appName in self?.callDetected(appName: appName) }
        detector.meetingEnded = { [weak self] in self?.callEnded() }
        // A call app using the microphone, or playing (muted): Stop when the call ends watches them.
        detector.callAppsChanged = { [weak self] input, output in
            self?.recorder.callAppRunning = input
            self?.recorder.callAppPlaying = output
        }
        return detector
    }

    /// A call started while Silvanus isn't recording: offer to record it, once.
    func callDetected(appName: String?) {
        guard !recorder.isRecording else { return }
        detectedCall = DetectedCall(appName: appName)
        meetingPrompt?.show(appName: appName)
    }

    /// The call ended: a prompt still up is stale.
    func callEnded() {
        detectedCall = nil
        meetingPrompt?.hide()
    }

    /// The prompt's Record meeting and the menu bar's Record Meeting: records like ⇧⌘R,
    /// after checking that it can (the permissions sheet opens in the main window if not).
    func recordDetectedCall() {
        meetingPrompt?.hide()
        record(.startRecording)
        if permissionsRequest != nil {
            NSApp.activate()
            NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
        }
    }

    /// Seeds when asked (scratch stores only), then reads the meetings from disk.
    convenience init(root: URL) {
        // Test, snapshot, and self-test runs (scratch stores) delete instead of using the real Trash.
        let library = Store.isScratch
            ? MeetingLibrary(root: root, trash: { try FileManager.default.removeItem(at: $0) })
            : MeetingLibrary(root: root)
        self.init(library: library)
        SeedData.seedIfRequested(library: library)
        reload()
        startRecordingServices()
    }

    /// Hides or shows the sidebar, sliding the canvas with the kit's selection curve.
    func toggleSidebar() {
        // Settings keeps its list on screen; the hide button is its back button then.
        guard !settingsOpen else { return }
        withAnimation(Motion.select) { sidebarVisible.toggle() }
    }

    /// Settings…, ⌘,: Settings takes the canvas column, and the sidebar column shows its list.
    /// `pane` picks the pane to show; nil keeps the last one.
    func openSettings(_ pane: SettingsPane? = nil) {
        if let pane { settingsPane = pane }
        settingsOpen = true
    }

    /// The back button and Escape: back to the meeting.
    func closeSettings() {
        settingsOpen = false
    }

    /// False while the meeting records or transcribes (or waits to): its files are in use.
    func canTrash(_ id: String) -> Bool { !recorder.isBusy(id) }

    /// The tooltip on Move to Trash: why it's off, when it is.
    func trashHelp(_ id: String?) -> String {
        guard let id, recorder.isBusy(id) else { return "Move this meeting to the Trash (⌘⌫)" }
        return recorder.meetingID == id ? "Stop recording before moving this meeting to the Trash"
            : "Wait for transcription to finish before moving this meeting to the Trash"
    }

    /// Meeting > Move to Trash (⌘⌫) and the sidebar row's menu. A failure shows the
    /// system's reason, and the meeting stays. A meeting that records or transcribes stays.
    func trash(_ id: String) {
        trashRequests.append(id)
        guard canTrash(id) else { return }
        do {
            try moveToTrash(id)
        } catch {
            NSApp.presentError(error)
        }
    }

    /// Moves a meeting to the Trash, after its open notes are saved, and reloads.
    func moveToTrash(_ id: String) throws {
        beforeTrash?(id)
        try library.moveToTrash(id)
        if selection == id { selection = nil }
        reload()
    }

    /// The notes canvas saved a meeting's notes: keep the app's copy the same, so nothing
    /// that saves the meeting later writes older notes.
    func notesSaved(_ text: String, for id: String) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        meetings[index].notes = text
    }

    func reload() {
        let loaded = library.loadAll()
        meetings = loaded.meetings
        unreadable = loaded.unreadable
        ownTodo = library.readOwnTodo()
    }

    private func regroup() {
        regroupCount += 1
        visibleMeetings = SidebarFolders.filter(meetings, folder: folder)
        dayGroups = DayGroups.days(visibleMeetings, now: now, calendar: .current)
        sidebarOrder = dayGroups.flatMap(\.meetings).map(\.id)
    }

    /// Opens a meeting: a click on its row, or Return on the selected one. The canvas shows
    /// the selected meeting; once it has a text view it takes keyboard focus here too.
    func open(_ id: String) {
        showingTodos = false
        selection = id
    }

    /// The open meeting, if any.
    var selectedMeeting: Meeting? {
        guard let selection else { return nil }
        return meetings.first { $0.id == selection }
    }

    /// Switches the canvas, sliding the view pill's segment with the kit's selection curve.
    func show(_ mode: CanvasMode) {
        settingsOpen = false
        withAnimation(Motion.select) { canvasMode = mode }
    }

    /// New Meeting (⌘N, the sidebar's new meeting button): a meeting page for notes, without
    /// recording, filed in the folder the sidebar shows. It opens on My notes.
    @discardableResult
    func newMeeting(now: Date = Date(), title: String = Meeting.untitled, attendees: [String] = []) -> Meeting? {
        let meeting = Meeting(info: MeetingInfo(title: title, start: now, attendees: attendees, folder: folder))
        // The full save is safe here: a new id gets a new folder, so there's nothing to overwrite.
        guard (try? library.save(meeting)) != nil else { return nil }
        settingsOpen = false
        let index = meetings.firstIndex { $0.info.start <= meeting.info.start } ?? meetings.endIndex
        meetings.insert(meeting, at: index)
        open(meeting.id)
        canvasMode = .notes
        return meeting
    }

    /// Renames a meeting on disk and in the sidebar. Spaces are tidied; an empty title is
    /// ignored (the old one stays, nothing is written). The folder on disk keeps its name.
    func rename(_ id: String, to title: String) {
        let cleaned = MeetingTitle.clean(title)
        guard !cleaned.isEmpty else { return }
        update(id) { $0.info.title = cleaned }
    }

    /// Meeting > Rename Meeting…: the open meeting's title turns editable. The header lives
    /// on Summary and My notes, so Transcript switches to My notes first.
    func requestRename() { request(.rename) }

    /// Meeting > Show Attendees: opens the date chip's list of attendees.
    func requestAttendees() { request(.attendees) }

    /// Meeting > Move to Folder > New Folder…: asks for a folder name.
    func requestNewFolder() { request(.newFolder) }

    /// The meeting header calls this once it has acted on `headerRequest`.
    func headerRequestHandled() {
        if let headerRequest { handledHeaderRequests.append(headerRequest) }
        headerRequest = nil
    }

    private func request(_ request: HeaderRequest) {
        headerRequest = request
        if canvasMode == .transcript { show(.notes) }
    }

    /// Files a meeting in a sidebar folder, or takes it out of one (nil).
    func setFolder(_ id: String, to name: String?) {
        let cleaned = name.map(MeetingTitle.clean).flatMap { $0.isEmpty ? nil : $0 }
        update(id) { $0.info.folder = cleaned }
    }

    /// Start Recording (⇧⌘R, the canvas header's Record button), or Stop while a meeting
    /// records. It records into the open meeting when that has no audio yet
    /// (`RecordingRules`), otherwise into a new meeting titled with the date and time.
    func startRecording() {
        if recorder.isRecording {
            recorder.stop()
        } else {
            record(.startRecording)
        }
    }

    /// The meeting Start Recording would record into, or nil for a new one.
    var recordingTarget: String? {
        guard let meeting = selectedMeeting, !settingsOpen else { return nil }
        let audio = library.audioURL(for: meeting.id)
        let files = audio.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        let transcript = library.notesURL(for: meeting.id)?.deletingLastPathComponent()
            .appending(path: MeetingFolder.transcriptJSON)
        let hasTranscript = transcript.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        return RecordingRules.canRecord(into: meeting, hasAudio: RecordingRules.hasSegments(files),
                                        hasTranscript: hasTranscript) ? meeting.id : nil
    }

    /// Starts a recording now, or opens the permissions sheet when access is missing. The
    /// sheet's Start Recording comes back with `fromSheet`: it needs only the microphone, and
    /// system audio never blocks (it's a warning if call audio can't start).
    func record(_ request: RecordRequest, fromSheet: Bool = false) {
        guard !recorder.isRecording else { return }
        let ready = fromSheet ? recorder.micReady() : recorder.permissionsReady()
        guard ready else {
            permissionsRequest = request
            return
        }
        permissionsRequest = nil
        do {
            try recorder.start(into: request == .quickNote ? nil : recordingTarget, quickNote: request == .quickNote)
            meetingPrompt?.hide()
            detectedCall = nil
        } catch {
            print("RECORDER couldn't start: \(error.localizedDescription)")
        }
    }

    /// A word or a timestamp in the Transcript view was clicked: play from `time`. Playback is
    /// wired in after calls; until then the transcript only shows the time.
    func seek(_ time: TimeInterval) { lastSeek = time }

    /// Quick Note (⌥⌘N, the canvas header's mic): a new meeting that records right away.
    func quickNote() {
        record(.quickNote)
    }

    /// Saves a change to one meeting's details (`meeting.json` only, never the notes or other
    /// files from this copy), then puts it back in `meetings` so the sidebar refreshes. A
    /// failed save changes nothing.
    private func update(_ id: String, _ change: (inout Meeting) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        var meeting = meetings[index]
        change(&meeting)
        guard meeting.info != meetings[index].info, (try? library.saveInfo(meeting)) != nil else { return }
        meetings[index] = meeting
    }
}

/// A call waiting to be recorded: the app using the microphone, when detection can name it.
struct DetectedCall: Equatable {
    var appName: String?
}

/// What the permissions sheet starts once access is given.
enum RecordRequest: Identifiable, Equatable {
    case startRecording, quickNote

    var id: Self { self }
}
