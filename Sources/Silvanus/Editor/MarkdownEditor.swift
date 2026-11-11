import AppKit
import SilvanusKit
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
    /// A page header that scrolls with the notes, above the first line (the meeting
    /// header on My notes), and its height. The text's first line box starts right under it.
    var header: AnyView? = nil
    var headerHeight: CGFloat = 0
    /// What VoiceOver calls the text view itself ("My notes"), not the scroll view around it.
    var accessibilityLabel: String? = nil
    /// The Summary page: selectable and findable, never edited or saved.
    var readOnly = false
    /// The Summary page with to-dos: how much of the text's start and end can't be changed.
    var locked: (prefix: Int, suffix: Int) = (0, 0)
    /// Timestamps for the trailing margin (My notes while recording); nil for none.
    var marginTimes: NoteTimes? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, view) = NotesTextView.scrollable()
        if let accessibilityLabel { view.setAccessibilityLabel(accessibilityLabel) }
        if readOnly { view.makeReadOnly() }
        if let header {
            scroll.documentView = HeaderedNotesView(header: header, height: headerHeight, textView: view)
        }
        let coordinator = context.coordinator
        view.delegate = coordinator
        coordinator.view = view
        view.load(text)
        view.locked = locked
        view.marginTimes = marginTimes
        coordinator.known = text
        view.onCharactersChanged = { [weak coordinator] in coordinator?.edited() }
        link?.attach(view: view, coordinator: coordinator)
        onReady?(view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let header, let page = scroll.documentView as? HeaderedNotesView {
            page.header.rootView = header
        }
        link?.attach(view: context.coordinator.view, coordinator: context.coordinator)
        context.coordinator.take(text)
        context.coordinator.view?.locked = locked
        context.coordinator.view?.marginTimes = marginTimes
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

        /// A change to the characters (typing, paste, undo, redo): count it and make sure
        /// a push is coming. No copy of the text. Undo and redo don't always reach
        /// `textDidChange`, so this hangs off the storage's own edits.
        func edited() {
            guard !taking else { return }
            parent.link?.onTyping?()
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
            // In place and undoable, even when the new text is empty: never a reload.
            view.applyExternal(text)
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

    /// Called on each keystroke (cheap: nothing is copied), so the owner can bound how
    /// long typing stays unsaved.
    var onTyping: (() -> Void)?

    /// Shows `text` (from disk) right away, keeping the caret on the same words.
    func show(_ text: String) { coordinator?.take(text) }
}

/// The notes scroll view's document when the page has a header: the header (SwiftUI) on
/// top and the text view under it, so they scroll as one page. The text view sizes its own
/// height as the note grows; this view follows it, and its width follows the scroll view.
final class HeaderedNotesView: NSView {
    let header: NSHostingView<AnyView>
    let textView: NotesTextView
    /// Where the text view starts: its top inset ends where the header does, so the first
    /// line box starts at the header's bottom.
    private var textTop: CGFloat { max(0, headerHeight - textView.textContainerInset.height) }
    private let headerHeight: CGFloat

    override var isFlipped: Bool { true }

    init(header: AnyView, height: CGFloat, textView: NotesTextView) {
        self.header = NSHostingView(rootView: header)
        self.textView = textView
        headerHeight = height
        super.init(frame: NSRect(x: 0, y: 0, width: textView.frame.width, height: height))
        autoresizingMask = [.width]
        textView.autoresizingMask = []
        textView.postsFrameChangedNotifications = true
        addSubview(textView)
        // Over the text view's top inset, so the header's controls take their clicks.
        addSubview(self.header)
        // Tab past the header's last control lands in the notes. A window that recalculates its
        // key view loop puts the text view next anyway: it's below the header.
        self.header.nextKeyView = textView
        // A selector observer goes away with this view on its own.
        NotificationCenter.default.addObserver(self, selector: #selector(textFrameChanged),
                                               name: NSView.frameDidChangeNotification, object: textView)
        placeParts()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func textFrameChanged(_ note: Notification) {
        fitHeight()
    }

    /// VoiceOver reads the header (title, then chips), then the notes, as on screen.
    override func accessibilityChildren() -> [Any]? {
        [header, textView]
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        placeParts()
    }

    /// The header across the top, the text view under it at the full width.
    private func placeParts() {
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        let wanted = NSRect(x: 0, y: textTop, width: bounds.width, height: textView.frame.height)
        if textView.frame != wanted { textView.frame = wanted }
        fitHeight()
    }

    /// Tall enough for the header and the whole note.
    private func fitHeight() {
        let height = textTop + textView.frame.height
        if frame.height != height { setFrameSize(NSSize(width: frame.width, height: height)) }
    }
}
