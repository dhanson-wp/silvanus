import AppKit
import SilvanusKit
import SwiftUI

/// The selected meeting's notes, in the canvas column under the 46 pt header band
/// (PaneLayout's `canvas` slot; the header itself is the canvas header's). Text starts
/// at x 221 and the first line's cap top at y 64, per design/KIT.md "Notes canvas text".
struct NotesCanvas: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let id = model.selection, model.meetings.contains(where: { $0.id == id }) {
            NotesPane(meetingID: id, library: model.library)
                // A new meeting gets a new document and editor; the old one saves first.
                .id(id)
        } else {
            Text("Pick a meeting or start one")
                .kitType(.subheading)
                .foregroundStyle(Ink.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// One meeting's notes: the document opens when the pane appears and saves and closes
/// when it goes away.
private struct NotesPane: View {
    let meetingID: String
    let library: MeetingLibrary
    @State private var document: NotesDocument?

    var body: some View {
        Group {
            if let document {
                NotesEditor(document: document)
            } else {
                Color.clear
            }
        }
        .onAppear { document = document ?? NotesDocument(meetingID: meetingID, library: library) }
        .onDisappear { document?.close() }
    }
}

struct NotesEditor: View {
    @Bindable var document: NotesDocument

    var body: some View {
        MarkdownEditor(text: $document.text, link: document.link)
            .accessibilityLabel("My notes")
    }
}

/// A meeting's `notes.md` while the canvas shows it. Typing reaches `text` when it
/// pauses (MarkdownEditor); the file is written 1 s after the last change, when the
/// window closes, when the app quits, and when another meeting is picked. A change to
/// the file from another app is shown in place, unless there's typing not yet saved
/// (`NotesSync` decides; that typing is saved over it).
@Observable
@MainActor
final class NotesDocument {
    let meetingID: String
    let link = EditorLink()
    /// The note as Markdown. Set by the editor when typing pauses.
    var text: String {
        didSet { if !applyingDisk { changed() } }
    }
    /// True when `text` has changes not yet written.
    private(set) var isDirty = false
    /// For the checks: files written, and changes taken from disk.
    @ObservationIgnored private(set) var saves = 0
    @ObservationIgnored private(set) var reloads = 0
    /// Seconds after the last change before the file is written.
    @ObservationIgnored var saveDelay: TimeInterval = 1

    private let library: MeetingLibrary
    @ObservationIgnored private var sync: NotesSync
    @ObservationIgnored private var applyingDisk = false
    @ObservationIgnored private var closed = false
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(meetingID: String, library: MeetingLibrary) {
        self.meetingID = meetingID
        self.library = library
        let loaded = library.readNotes(for: meetingID) ?? ""
        text = loaded
        sync = NotesSync(loaded: loaded)
        if let url = library.notesURL(for: meetingID) {
            watcher = FileWatcher(url: url) { [weak self] in self?.diskChanged() }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            let closing = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, let closing, closing === self.link.window else { return }
                self.saveNow()
            }
        })
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        })
    }

    private func changed() {
        isDirty = true
        if closed { saveNow(); return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }

    /// Writes the note now if anything changed, taking any typing still in the editor.
    func saveNow() {
        link.flush()
        saveWork?.cancel()
        saveWork = nil
        guard isDirty else { return }
        do {
            try library.saveNotes(text, for: meetingID)
            sync.saved(text)
            isDirty = false
            saves += 1
        } catch {
            // Stays dirty: the next change or close tries again.
            print("NOTES save failed for \(meetingID): \(error)")
        }
    }

    /// The file changed on disk: our own save, or another app's edit.
    func diskChanged() {
        guard !closed else { return }
        link.flush()
        let disk = library.readNotes(for: meetingID)
        guard let fresh = sync.diskChanged(to: disk, editor: text, editorDirty: isDirty) else { return }
        reloads += 1
        applyingDisk = true
        text = fresh
        applyingDisk = false
        link.show(fresh)
    }

    /// Saves and stops watching. Later changes (the editor's last push) save at once.
    func close() {
        saveNow()
        closed = true
        watcher = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }
}

/// Calls `onChange` (on the main queue, coalesced) when a file changes on disk, whether
/// it's written in place or replaced (an atomic save renames a new file over it). It
/// watches the folder for replacements and the file itself for in-place writes,
/// reopening the file after each replacement.
final class FileWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private var folderSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var scheduled = false
    /// Events within this window become one call.
    static let coalesce: TimeInterval = 0.1

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
        folderSource = Self.source(for: url.deletingLastPathComponent(), mask: [.write]) { [weak self] in
            self?.watchFile()
            self?.fire()
        }
        watchFile()
    }

    deinit {
        folderSource?.cancel()
        fileSource?.cancel()
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = Self.source(for: url, mask: [.write, .extend, .delete, .rename]) { [weak self] in
            self?.fire()
        }
    }

    private func fire() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.coalesce) { [weak self] in
            guard let self else { return }
            scheduled = false
            MainActor.assumeIsolated { onChange() }
        }
    }

    private static func source(for url: URL, mask: DispatchSource.FileSystemEvent,
                               handler: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }
}
