import AppKit
import SilvanusKit
import SwiftUI

/// The selected meeting's notes, in the canvas column under the 46 pt header band
/// (PaneLayout's `canvas` slot; the header itself is the canvas header's). Text starts
/// at x 221 and the first line's cap top at y 64, per design/KIT.md "Notes canvas text".
struct NotesCanvas: View {
    @Environment(AppModel.self) private var model
    @State private var documents = OpenNotes()

    var body: some View {
        if let id = model.selection, model.meetings.contains(where: { $0.id == id }) {
            NotesEditor(document: documents.open(id, model: model))
                // A new meeting gets a new editor; the old one hands over its typing as it goes.
                .id(id)
        } else {
            Text("Pick a meeting or start one")
                .kitType(.subheading)
                .foregroundStyle(Ink.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The notes documents the canvas has open: the selected meeting's, and, for a moment
/// after picking another, the one it replaced. Old documents close when the selection
/// changes (`AppModel.selectionChanged`, not the view body), on the next turn of the run loop, once their editor has handed over its
/// last typing, so the close saves everything. It also saves the open notes before the
/// app trashes that meeting.
@MainActor final class OpenNotes {
    private(set) var current: NotesDocument?
    private var replaced: [NotesDocument] = []

    func open(_ id: String, model: AppModel) -> NotesDocument {
        model.selectionChanged = { [weak self] selected in self?.closeAll(except: selected) }
        model.beforeTrash = { [weak self] trashed in
            guard let self else { return }
            for document in [current].compactMap({ $0 }) + replaced where document.meetingID == trashed {
                document.saveNow()
            }
        }
        if let current, current.meetingID == id { return current }
        if let current { replaced.append(current) }
        let document = NotesDocument(meetingID: id, library: model.library)
        document.onSaved = { [weak model] text in model?.notesSaved(text, for: id) }
        current = document
        return document
    }

    /// Closes every open document but the one for `id`.
    func closeAll(except id: String?) {
        var closing = replaced
        replaced = []
        if let current, current.meetingID != id {
            closing.append(current)
            self.current = nil
        }
        guard !closing.isEmpty else { return }
        DispatchQueue.main.async { for document in closing { document.close() } }
    }
}

/// The editor for one document, with the save error banner over its bottom edge.
struct NotesEditor: View {
    @Bindable var document: NotesDocument

    var body: some View {
        MarkdownEditor(text: $document.text, link: document.link)
            .accessibilityLabel("My notes")
            .overlay(alignment: .bottom) {
                if let error = document.saveError {
                    SaveErrorBanner(reason: error, retry: document.saveNow)
                        .padding(.bottom, 12)
                }
            }
    }
}

/// "Couldn't save notes: <reason>" with Retry. Not modal: typing goes on, and the next
/// save or Retry clears it.
private struct SaveErrorBanner: View {
    let reason: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Couldn't save notes: \(reason)")
                .kitType(.label)
                .foregroundStyle(Ink.text)
                .lineLimit(2)
            Button("Retry", action: retry)
                .kitType(.button)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Ink.canvas, in: RoundedRectangle(cornerRadius: Metric.buttonCorner))
        .overlay(RoundedRectangle(cornerRadius: Metric.buttonCorner).stroke(Ink.divider, lineWidth: Metric.hairline))
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }
}

/// A meeting's `notes.md` while the canvas shows it. Typing reaches `text` when it
/// pauses (MarkdownEditor); the file is written 1 s after the last change, at least every
/// 3 s while typing goes on, when the window closes, when the app quits, and when another
/// meeting is picked. A change to the file from another app is shown in place; with
/// unsaved typing it's merged, or, when both changed the same lines, the typing stays and
/// the other version is kept beside the notes (`NotesSync` decides).
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
    /// Why the last save failed, until a save works.
    private(set) var saveError: String?
    /// Called with the text after each save, so the app's copy of the meeting stays current.
    @ObservationIgnored var onSaved: ((String) -> Void)?
    /// For the checks: files written, changes taken from disk, and conflict copies kept.
    @ObservationIgnored private(set) var saves = 0
    @ObservationIgnored private(set) var reloads = 0
    @ObservationIgnored private(set) var conflicts: [URL] = []
    @ObservationIgnored private(set) var recovered: [URL] = []
    /// Writes the other app's version beside the notes. The checks swap in one that fails.
    @ObservationIgnored var writeConflictCopy: (String) throws -> URL
    /// Seconds after the last change before the file is written.
    @ObservationIgnored var saveDelay: TimeInterval = 1
    /// The longest typing goes unsaved while it never pauses for `saveDelay`.
    @ObservationIgnored var maxWait: TimeInterval = 3

    private let library: MeetingLibrary
    @ObservationIgnored private var sync: NotesSync
    @ObservationIgnored private var applyingDisk = false
    @ObservationIgnored private var closed = false
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var maxWaitWork: DispatchWorkItem?
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Another app's version that must be copied beside the notes before ours is saved.
    @ObservationIgnored private var pendingConflict: String?

    init(meetingID: String, library: MeetingLibrary) {
        self.meetingID = meetingID
        self.library = library
        writeConflictCopy = { [library] text in try library.saveConflictCopy(text, for: meetingID) }
        let loaded = library.readNotes(for: meetingID) ?? ""
        text = loaded
        sync = NotesSync(loaded: loaded)
        if let url = library.notesURL(for: meetingID) {
            watcher = FileWatcher(url: url) { [weak self] in self?.diskChanged() }
        }
        link.onTyping = { [weak self] in self?.startMaxWait() }
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
        startMaxWait()
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }

    /// The first unsaved keystroke starts a clock: the note is saved `maxWait` later even
    /// if typing never pauses.
    private func startMaxWait() {
        guard maxWaitWork == nil, !closed else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.maxWaitWork = nil
            self?.saveNow()
        }
        maxWaitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + maxWait, execute: work)
    }

    /// Writes the note now if anything changed, taking any typing still in the editor.
    /// With another app's conflicting version waiting, that version is copied beside the
    /// notes first, and nothing is written over `notes.md` until the copy exists. When the
    /// meeting's folder is gone (trashed, deleted), the text goes to `recovered/`.
    func saveNow() {
        link.flush()
        saveWork?.cancel()
        saveWork = nil
        maxWaitWork?.cancel()
        maxWaitWork = nil
        guard isDirty else { return }
        if let theirs = pendingConflict {
            do {
                conflicts.append(try writeConflictCopy(theirs))
                pendingConflict = nil
                print("NOTES \(meetingID): another app changed the same lines; kept its version as \(conflicts.last?.lastPathComponent ?? "")")
            } catch {
                // notes.md keeps the other version until Retry or the next save gets the copy out.
                saveError = Self.reason(error)
                print("NOTES \(meetingID): couldn't keep the other version, so notes.md is left as it is: \(error)")
                return
            }
        }
        do {
            try library.saveNotes(text, for: meetingID)
            sync.saved(text)
            isDirty = false
            saveError = nil
            saves += 1
            onSaved?(text)
        } catch where !library.folderExists(for: meetingID) {
            recover()
        } catch {
            // Stays dirty: the banner's Retry, the next change, or closing tries again.
            saveError = Self.reason(error)
            print("NOTES save failed for \(meetingID): \(error)")
        }
    }

    /// The meeting's folder is gone: keep the text under the store's `recovered/`.
    private func recover() {
        do {
            let url = try library.saveRecoveredNotes(text, for: meetingID)
            recovered.append(url)
            sync.saved(text)
            isDirty = false
            print("NOTES \(meetingID): the meeting's folder is gone; kept the notes as \(url.path)")
        } catch {
            saveError = Self.reason(error)
            print("NOTES \(meetingID): the meeting's folder is gone and the notes couldn't be kept: \(error)")
        }
    }

    private static func reason(_ error: Error) -> String {
        (error as NSError).localizedDescription
    }

    /// The file changed on disk: our own save, or another app's edit.
    func diskChanged() {
        guard !closed else { return }
        link.flush()
        let disk = library.readNotes(for: meetingID)
        switch sync.diskChanged(to: disk, editor: text, editorDirty: isDirty) {
        case .none:
            return
        case .show(let fresh):
            reloads += 1
            show(fresh)
        case .merged(let merged):
            reloads += 1
            show(merged)
            isDirty = true
            saveNow()
        case .conflict(let theirs):
            pendingConflict = theirs
            isDirty = true
            saveNow()
        }
    }

    /// Puts disk text in the editor as one undoable step, without counting it as typing.
    private func show(_ fresh: String) {
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
