import AppKit
import SwiftUI

/// The notes canvas in SwiftUI: one NotesTextView on TextKit 2. The binding
/// holds the note exactly as Markdown; styling lives only in attributes.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    /// Called once with the text view, for the spike's snapshots and checks.
    var onReady: ((NotesTextView) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let (scroll, view) = NotesTextView.scrollable()
        view.delegate = context.coordinator
        view.load(text)
        onReady?(view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NotesTextView, !context.coordinator.isEditing else { return }
        if view.string != text { view.load(text) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var isEditing = false
        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            isEditing = true
            parent.text = view.string
            isEditing = false
        }
    }
}
