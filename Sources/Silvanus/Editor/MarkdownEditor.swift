import AppKit
import SwiftUI

/// The notes canvas in SwiftUI: one NotesTextView on TextKit 2. The binding holds the
/// note exactly as Markdown; styling lives only in attributes.
///
/// Typing never touches the binding keystroke by keystroke: the coordinator counts
/// edits and hands the text over once typing pauses for `pushDelay` (or when `link`
/// flushes it, before a save). A value coming back through the binding that is the
/// text it handed over is recognized without reading the view's text, so the
/// editor's own edits are never loaded back into it.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    /// Lets the owner flush typing into the binding and apply changes from disk.
    var link: EditorLink? = nil
    /// How long typing pauses before the binding gets the text.
    var pushDelay: TimeInterval = 0.25
    /// Called once with the text view, for the spike's snapshots and checks.
    var onReady: ((NotesTextView) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, view) = NotesTextView.scrollable()
        let coordinator = context.coordinator
        view.delegate = coordinator
        coordinator.view = view
        view.load(text)
        coordinator.known = text
        link?.attach(view: view, coordinator: coordinator)
        onReady?(view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        link?.attach(view: context.coordinator.view, coordinator: context.coordinator)
        context.coordinator.take(text)
    }

    /// Typing not yet handed over goes to the binding before the editor goes away.
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.push()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var view: NotesTextView?
        /// Edits made in the view, and how many of them the binding has seen.
        private(set) var version = 0
        private(set) var pushedVersion = 0
        /// For the checks: times the text went to the binding.
        private(set) var pushes = 0
        /// The text the view and the binding last agreed on: what was loaded, taken, or
        /// handed over. The binding's echo of a push is this same string value, so
        /// comparing against it ends at the first check (same storage) instead of
        /// walking the whole note.
        fileprivate(set) var known = ""
        private var lastEdit: CFAbsoluteTime = 0
        private var pushScheduled = false
        /// True while a value from the binding is applied: not typing, so not counted.
        private var taking = false

        init(_ parent: MarkdownEditor) { self.parent = parent }

        var hasUnpushedEdits: Bool { version != pushedVersion }

        /// A keystroke: count it and make sure a push is coming. No copy of the text.
        func textDidChange(_ notification: Notification) {
            guard !taking else { return }
            version += 1
            lastEdit = CFAbsoluteTimeGetCurrent()
            schedulePush(after: parent.pushDelay)
        }

        private func schedulePush(after delay: TimeInterval) {
            guard !pushScheduled else { return }
            pushScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                pushScheduled = false
                // Still typing: wait out the rest of the pause.
                let idle = CFAbsoluteTimeGetCurrent() - lastEdit
                if idle < parent.pushDelay {
                    schedulePush(after: parent.pushDelay - idle)
                } else {
                    push()
                }
            }
        }

        /// Hands the view's text to the binding, if it changed since the last time.
        func push() {
            guard hasUnpushedEdits, let view else { return }
            let text = view.string
            known = text
            pushedVersion = version
            pushes += 1
            parent.text = text
        }

        /// A value from the binding. Its own echo, or a value already shown, is ignored;
        /// anything else replaces the text, changing only the part that differs so the
        /// caret stays where it was.
        func take(_ text: String) {
            guard let view, text != known else { return }
            known = text
            taking = true
            defer { taking = false }
            if view.string.isEmpty || text.isEmpty {
                view.load(text)
            } else {
                view.applyExternal(text)
            }
            // Typing the binding never saw is replaced along with the rest.
            pushedVersion = version
        }
    }
}

/// Connects a MarkdownEditor to whoever owns its text (the notes canvas's document):
/// flush typing into the binding before a save, and apply text read from disk.
@MainActor final class EditorLink {
    private(set) weak var textView: NotesTextView?
    private weak var coordinator: MarkdownEditor.Coordinator?

    fileprivate func attach(view: NotesTextView?, coordinator: MarkdownEditor.Coordinator) {
        textView = view
        self.coordinator = coordinator
    }

    /// The window the editor is in, once it's on screen.
    var window: NSWindow? { textView?.window }

    /// Typing the binding hasn't seen yet goes to it now.
    func flush() { coordinator?.push() }

    /// True when the view holds typing the binding hasn't seen.
    var hasUnpushedEdits: Bool { coordinator?.hasUnpushedEdits ?? false }

    /// Shows `text` (from disk) right away, keeping the caret on the same words.
    func show(_ text: String) { coordinator?.take(text) }
}
