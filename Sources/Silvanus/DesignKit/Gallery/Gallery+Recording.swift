import SwiftUI

/// The recording family in the kit gallery: the floating recording pill in each state
/// (recording, a warning on the line, stopping, failed), the live wave on its own and in the
/// view pill, the Transcribing… indicator at a few points, and the notice banner. Fictional
/// words only.
struct RecordingGallery: View {
    /// A fixed meter, so the waves look the same in every capture.
    static let meter = LevelMeter(levels: [0.08, 0.35, 0.7, 0.25, 0.5])
    /// 12 minutes 34 seconds before the moment the gallery is drawn.
    private var since: Date { Date().addingTimeInterval(-754) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Recording")
                .kitType(.section)
                .foregroundStyle(Ink.textSecondary)
            HStack(alignment: .top, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.lg) {
                    sample("Recording pill") {
                        RecordingPill(status: .recording(since: since), line: "Acme kickoff", meter: Self.meter, open: {}, stop: {})
                    }
                    sample("With a warning") {
                        RecordingPill(status: .recording(since: since), line: Recorder.silentCall, meter: Self.meter,
                                      open: {}, stop: {})
                    }
                    sample("Stopping") {
                        RecordingPill(status: .stopping, line: "Acme kickoff", meter: Self.meter, open: {}, stop: {})
                    }
                    sample("Failed") {
                        RecordingPill(status: .failed("Couldn't write audio: The disk is full."), line: "Acme kickoff",
                                      meter: Self.meter, open: {}, stop: {})
                    }
                }
                VStack(alignment: .leading, spacing: Space.lg) {
                    sample("Live wave") {
                        HStack(spacing: Space.lg) {
                            LiveWave(meter: Self.meter).foregroundStyle(Ink.recordingText)
                            LiveWave(meter: LevelMeter()).foregroundStyle(Ink.recordingText)
                        }
                    }
                    sample("View pill, recording") {
                        ViewPill(mode: .constant(.notes), meter: Self.meter)
                    }
                    sample("Transcribing") {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            TranscribingIndicator(progress: 0)
                            TranscribingIndicator(progress: 0.45)
                            TranscribingIndicator(progress: 1)
                        }
                    }
                    sample("Banner") {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            NoticeBanner(message: "Couldn't transcribe this meeting: The audio couldn't be read.",
                                         actionTitle: "Retry", action: {}, dismiss: {})
                            NoticeBanner(message: "Finished transcribing an interrupted recording", dismiss: {})
                        }
                        .frame(width: Metric.recordingPillWidth + Space.section * 2)
                    }
                }
            }
            .padding(Space.lg)
            .background(Ink.canvas, in: RoundedRectangle(cornerRadius: Metric.rowCorner))
            .overlay(RoundedRectangle(cornerRadius: Metric.rowCorner).strokeBorder(Ink.divider, lineWidth: Metric.hairline))
        }
    }

    private func sample(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .kitType(.meta)
                .foregroundStyle(Ink.textSecondary)
            content()
                .environment(\.onCanvas, true)
        }
    }
}
