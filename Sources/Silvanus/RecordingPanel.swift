import AppKit
import SilvanusKit
import SwiftUI

/// The recording controls' window (KIT.md "Recording controls"): a small non-activating
/// panel, always on top, on every Space and over full-screen apps, shown for the whole
/// recording whichever app is in front, Silvanus included. It's a persistent companion:
/// hiding it whenever Silvanus came forward would make it flicker each time focus moves
/// between the call and the notes, and Pause lives only here. Pause, Resume, Retry, and Stop
/// never activate Silvanus or take the keyboard from the call; only a plain click on the
/// grip does, so the arrow keys can move it.
///
/// It starts bottom center above the Dock on the main window's display, remembers where it
/// was left on each display, stays inside the screen's visible frame, and comes back onto a
/// screen when one is unplugged or changes size. Hiding it (the menu bar's Hide Recording
/// Controls) lasts for this recording; the menu bar keeps Show Recording Controls.
@MainActor
@Observable
final class RecordingPanel: BarMover {
    @ObservationIgnored private let recorder: Recorder
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var panel: ControlsPanel?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// The bar's bottom left corner, in screen points.
    @ObservationIgnored private(set) var barOrigin = NSPoint.zero
    @ObservationIgnored private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    @ObservationIgnored private var lastMode: Recorder.Mode = .idle
    @ObservationIgnored private var lastCallAudioDown: String?
    @ObservationIgnored private var lastCallEndStopAt: Date?
    @ObservationIgnored private var noteHeights: [String: CGFloat] = [:]
    /// True when the controls were hidden for this recording (the menu bar shows them again).
    private(set) var isHiddenByUser = false
    /// The last state change spoken to VoiceOver, for the checks.
    @ObservationIgnored private(set) var lastAnnouncement: String?

    /// The screens, and the main window's display: the self-test fakes them.
    @ObservationIgnored var screens: @MainActor () -> [BarPlacement.Screen] = RecordingPanel.liveScreens
    @ObservationIgnored var preferredScreen: @MainActor () -> String? = RecordingPanel.mainWindowScreen

    static let windowID = NSUserInterfaceItemIdentifier("silvanus.recordingControls")
    static let title = "Silvanus recording controls"
    static let positionsKey = "recordingControls.positions"
    static let displayKey = "recordingControls.display"

    init(recorder: Recorder, model: AppModel) {
        self.recorder = recorder
        self.model = model
        // An unplugged display or a new resolution must never strand the controls.
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        track()
        update()
    }

    var isShowing: Bool { panel != nil }
    /// The controls' window, for the checks and for telling it from the other panels.
    var window: NSWindow? { panel }
    var frame: NSRect? { panel?.frame }
    var barFrame: NSRect { NSRect(origin: barOrigin, size: NSSize(width: Metric.barWidth, height: Metric.barHeight)) }

    /// Updates when the recorder's state or call audio changes.
    private func track() {
        withObservationTracking {
            _ = recorder.mode
            _ = recorder.isRecording
            _ = recorder.callAudioDown
            _ = recorder.callEndStopAt
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.track()
            }
        }
    }

    func update() {
        let mode = recorder.mode
        if lastMode == .idle, mode != .idle { isHiddenByUser = false }
        announce(from: lastMode, to: mode)
        if mode == .recording, let stopAt = recorder.callEndStopAt, lastCallEndStopAt == nil {
            say(RecordingWords.callEndedNote(seconds: CallEndStop.secondsLeft(until: stopAt, at: .now)))
        }
        lastMode = mode
        lastCallAudioDown = recorder.callAudioDown
        lastCallEndStopAt = recorder.callEndStopAt
        if recorder.state.showsControls && !isHiddenByUser {
            show()
            place()
        } else {
            hide()
        }
    }

    /// Hide Recording Controls (menu bar): hidden for this recording. Hiding isn't stopping.
    func hideByUser() {
        isHiddenByUser = true
        update()
    }

    /// Show Recording Controls (menu bar).
    func showByUser() {
        isHiddenByUser = false
        update()
    }

    // MARK: - Window

    private func show() {
        guard panel == nil, let model else { return }
        let view = RecordingControlsHost(recorder: recorder, model: model, mover: self)
            .padding(Metric.barWindowMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        let host = BarHostingView(rootView: view)
        let p = ControlsPanel(contentRect: NSRect(origin: .zero, size: windowSize),
                              styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.contentView = host
        p.identifier = Self.windowID
        p.title = Self.title
        p.setAccessibilityLabel(Self.title)
        p.isFloatingPanel = true
        // Buttons act without making the panel key; only the grip's click asks for the keyboard.
        p.becomesKeyOnlyIfNeeded = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        // Only the grip moves the window; a click anywhere else is a click.
        p.isMovableByWindowBackground = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        panel = p
        let size = NSSize(width: Metric.barWidth, height: Metric.barHeight)
        let saved = Self.savedPositions()
        let resolved = BarPlacement.resolve(saved: saved, last: Self.savedDisplay(), preferred: preferredScreen(),
                                            screens: screens(), size: size, inset: Space.lg)
        barOrigin = resolved?.origin ?? .zero
        place()
        p.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        dragStart = nil
    }

    /// The note's height above the bar, plus its gap, while one shows.
    private var noteRoom: CGFloat {
        let countdown = recorder.mode == .recording && recorder.callEndStopAt != nil
        let text: String? = switch recorder.mode {
        case .paused: RecordingWords.pausedNote
        case .interrupted: RecordingWords.lostNote(track: Recorder.micTrack)
        // Measured at its longest, so the window doesn't change size as it counts.
        case .recording where countdown: RecordingWords.callEndedNote(seconds: 10)
        default: nil
        }
        guard let text else { return 0 }
        if let height = noteHeights[text] { return height + Metric.barNoteGap }
        let note = BarNote(text: text, action: countdown ? (RecordingWords.keepRecording, {}) : nil)
        let height = NSHostingView(rootView: note).fittingSize.height.rounded(.up)
        noteHeights[text] = height
        return height + Metric.barNoteGap
    }

    private var windowSize: NSSize {
        NSSize(width: Metric.barWidth + 2 * Metric.barWindowMargin,
               height: Metric.barHeight + noteRoom + 2 * Metric.barWindowMargin)
    }

    /// Keeps the bar (and its note) inside its screen and sizes the window around them. The
    /// window grows upward for the note; the bar holds still.
    private func place() {
        guard let panel else { return }
        let screen = BarPlacement.screen(for: barFrame, in: screens())
        if let screen {
            barOrigin = BarPlacement.clamp(barOrigin, size: barFrame.size, in: screen.visible)
        }
        // The note may push the window down near the top of the screen; that's a copy for
        // this frame only, so the spot the user chose stays as it was.
        let room = noteRoom
        let shown = screen.map { BarPlacement.clamp(barOrigin, size: barFrame.size, above: room, in: $0.visible) } ?? barOrigin
        let size = windowSize
        let frame = NSRect(x: shown.x - Metric.barWindowMargin, y: shown.y - Metric.barWindowMargin,
                           width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// A display came or went, or changed size: back where it was left on a display that's
    /// still there, else onto the main window's display.
    func screensChanged() {
        guard panel != nil else { return }
        let list = screens()
        let here = BarPlacement.screen(for: barFrame, in: list)
        let visible = here.map { $0.visible.intersects(barFrame) } ?? false
        if !visible {
            let resolved = BarPlacement.resolve(saved: Self.savedPositions(), last: Self.savedDisplay(),
                                                preferred: preferredScreen(), screens: list, size: barFrame.size,
                                                inset: Space.lg)
            barOrigin = resolved?.origin ?? barOrigin
        }
        place()
    }

    // MARK: - Moving (BarMover)

    func dragBegan(at point: NSPoint) {
        dragStart = (point, barOrigin)
    }

    func dragMoved(to point: NSPoint) {
        guard let start = dragStart else { return }
        barOrigin = NSPoint(x: start.origin.x + point.x - start.mouse.x, y: start.origin.y + point.y - start.mouse.y)
        place()
    }

    func dragEnded() {
        guard dragStart != nil else { return }
        dragStart = nil
        save()
    }

    func nudge(dx: CGFloat, dy: CGFloat) {
        barOrigin = NSPoint(x: barOrigin.x + dx, y: barOrigin.y + dy)
        place()
        save()
    }

    /// Reset Recording Controls Position, and Home on the grip: bottom center above the
    /// Dock on the main window's display, and that display forgets its saved spot.
    func resetPosition() {
        let list = screens()
        guard let screen = list.first(where: { $0.id == preferredScreen() }) ?? list.first else { return }
        var saved = Self.savedPositions()
        saved[screen.id] = nil
        Self.save(saved, display: nil)
        barOrigin = BarPlacement.defaultOrigin(size: barFrame.size, in: screen.visible, inset: Space.lg)
        place()
    }

    /// Remembers where the bar was left, on the display it's on.
    private func save() {
        guard let screen = BarPlacement.screen(for: barFrame, in: screens()) else { return }
        var saved = Self.savedPositions()
        saved[screen.id] = barOrigin
        Self.save(saved, display: screen.id)
    }

    // MARK: - Saved positions (AppDefaults)

    static func savedPositions(_ defaults: UserDefaults = AppDefaults.shared) -> [String: CGPoint] {
        let raw = defaults.dictionary(forKey: positionsKey) as? [String: String] ?? [:]
        return raw.mapValues { NSPointFromString($0) }
    }

    static func savedDisplay(_ defaults: UserDefaults = AppDefaults.shared) -> String? {
        defaults.string(forKey: displayKey)
    }

    private static func save(_ positions: [String: CGPoint], display: String?, to defaults: UserDefaults = AppDefaults.shared) {
        defaults.set(positions.mapValues { NSStringFromPoint($0) }, forKey: positionsKey)
        defaults.set(display, forKey: displayKey)
    }

    // MARK: - Screens

    static func liveScreens() -> [BarPlacement.Screen] {
        NSScreen.screens.map { BarPlacement.Screen(id: id(of: $0), visible: $0.visibleFrame) }
    }

    /// The display the main window is on, else the one with the menu bar's focus.
    static func mainWindowScreen() -> String? {
        let main = NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) && $0.isVisible }
        return (main?.screen ?? NSScreen.main).map(id(of:))
    }

    static func id(of screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
            ?? NSStringFromRect(screen.frame)
    }

    // MARK: - VoiceOver

    /// Speaks state changes, never the time or the level bars.
    private func announce(from old: Recorder.Mode, to new: Recorder.Mode) {
        var text: String?
        switch (old, new) {
        case (.idle, .recording): text = RecordingWords.recording
        case (_, .paused) where old != .paused && old != .interrupted: text = "\(RecordingWords.paused). \(RecordingWords.pausedNote)"
        case (.paused, .recording): text = "Recording resumed"
        case (.interrupted, .recording): text = "Audio is back. Recording."
        case (.interrupted, .paused): text = "Audio is back. \(RecordingWords.paused)."
        case (_, .interrupted) where old != .interrupted:
            text = "\(RecordingWords.audioLost). \(RecordingWords.lostNote(track: Recorder.micTrack))"
        case (_, .idle) where old != .idle: text = "Recording stopped"
        default: break
        }
        if new == .recording, text == nil, recorder.callAudioDown != lastCallAudioDown {
            text = recorder.callAudioDown == nil ? "Call audio is back" : "\(RecordingWords.micOnly). \(Recorder.micOnly)"
        }
        guard let text else { return }
        say(text)
    }

    private func say(_ text: String) {
        lastAnnouncement = text
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// A panel that can become key for the grip's arrow keys, never main.
final class ControlsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click act on the controls though the panel isn't key.
final class BarHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The controls with the recorder's values. Pause, Resume, Retry, and Stop act on the
/// recorder and never bring Silvanus forward.
struct RecordingControlsHost: View {
    let recorder: Recorder
    let model: AppModel
    weak var mover: BarMover?

    var body: some View {
        if let status {
            RecordingControls(status: status, callAudioDown: recorder.callAudioDown, warning: recorder.warning,
                              callEndStopAt: recorder.callEndStopAt, meter: recorder.meter,
                              togglePause: recorder.togglePause, retry: recorder.retryCapture, stop: recorder.stop,
                              keepRecording: recorder.keepRecording, mover: mover)
        }
    }

    private var status: RecordingControls.Status? {
        switch recorder.phase {
        case let .recording(since): .recording(since: since)
        case let .paused(elapsed): .paused(elapsed: elapsed)
        case let .interrupted(elapsed, reason): .lost(elapsed: elapsed, reason: reason)
        default: nil
        }
    }
}
