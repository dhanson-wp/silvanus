import SwiftUI

/// KIT.md "Canvas header": the trailing controls' spacing.
extension Metric {
    /// More's 28 pt hit area ends 9 before the window's edge, so its dots end at x 893 in a
    /// 910 pt window (17 from the edge).
    static let headerTrailing: CGFloat = 9
    /// The Record button ends 3 before More's hit area (x 870 in a 910 pt window).
    static let recordToMore: CGFloat = 3
    /// The Quick Note mic sits 8 before the Record button.
    static let micToRecord: CGFloat = 8
}

/// The canvas's 46 pt header band, from KIT.md "Canvas header": the view pill at the leading
/// edge (x 221), and on the trailing side, right to left from x 893, More, the Record button,
/// and the Quick Note mic. Every control is 28 tall at y 9. The folder is set from the
/// meeting header's folder chip, not here (one control for one thing).
///
/// With no meeting open (`hasMeeting` false) only the mic and Record button show.
/// It knows nothing of the editor or the model: it takes values and closures. A nil
/// `startRecording` or `quickNote` draws that control disabled.
struct CanvasHeader: View {
    @Binding var mode: CanvasMode
    var hasMeeting = true
    var isRecording = false
    /// Modes that can't be shown yet.
    var disabledModes: Set<CanvasMode> = []
    var startRecording: (() -> Void)?
    var quickNote: (() -> Void)?
    /// Nil until the meeting menu lands: More shows disabled.
    var more: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            if hasMeeting {
                ViewPill(mode: $mode, disabled: disabledModes)
                    .fixedSize()
                    .gridArea("headerPill", inset: 0)
            }
            Spacer(minLength: Metric.contentTrailing)
            QuickNoteButton(isRecording: isRecording, action: quickNote)
                .gridArea("headerMic", inset: 0)
                .padding(.trailing, Metric.micToRecord)
            RecordButton(isRecording: isRecording, action: startRecording)
                .fixedSize()
                .gridArea("headerRecord", inset: 0)
                .padding(.trailing, Metric.recordToMore)
            if hasMeeting {
                IconButton(.more, "More", help: "More actions for this meeting", action: more)
                    .gridArea("headerMore", inset: 0)
            } else {
                // Holds More's place, so the Record button stays put.
                Color.clear.frame(width: Metric.iconButton, height: Metric.iconButton)
            }
        }
        .padding(.trailing, Metric.headerTrailing)
        .padding(.top, Metric.controlY)
        .environment(\.onCanvas, true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
