import SwiftUI

/// The recording family in the kit gallery: the recording controls in each state
/// (recording, mic only, paused, audio lost, quiet, a long call, Reduce Motion), hover,
/// pressed, and focus on both buttons and the grip's hover, the Meeting detected prompt with
/// and without an app name, the live wave on its own and in the view pill, the Transcribing…
/// indicator at a few points, and the notice banner. Fictional words only.
struct RecordingGallery: View {
    /// A fixed meter, so the bars look the same in every capture.
    static let meter = LevelMeter(levels: [0.25, 0.55, 0.9, 0.45, 0.7])
    static let quiet = LevelMeter()
    /// 12 minutes 34 seconds before the moment the gallery is drawn.
    private var since: Date { Date().addingTimeInterval(-754) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Recording")
                .kitType(.section)
                .foregroundStyle(Ink.textSecondary)
            HStack(alignment: .top, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.lg) {
                    sample("Recording") { bar(.recording(since: since)) }
                    sample("Mic only") { bar(.recording(since: since), callAudioDown: "The call audio device stopped.") }
                    sample("Paused") { bar(.paused(elapsed: 754)) }
                    sample("Audio lost") { bar(.lost(elapsed: 754, reason: "Couldn't restart the microphone.")) }
                    sample("Quiet (flat bars)") { bar(.recording(since: since), meter: Self.quiet) }
                    sample("Long elapsed time") { bar(.recording(since: Date().addingTimeInterval(-7199))) }
                    sample("Reduce Motion") { bar(.recording(since: since), reduceMotion: true) }
                }
                VStack(alignment: .leading, spacing: Space.lg) {
                    sample("Pause hover, Stop hover") { bar(.recording(since: since), pause: .hover, stop: .hover) }
                    sample("Pause pressed, Stop pressed") { bar(.recording(since: since), pause: .pressed, stop: .pressed) }
                    sample("Pause focused") { bar(.recording(since: since), pause: .focused) }
                    sample("Stop focused") { bar(.recording(since: since), stop: .focused) }
                    sample("Resume hover") { bar(.paused(elapsed: 754), pause: .hover) }
                    sample("Retry focused") { bar(.lost(elapsed: 754, reason: "Couldn't restart the microphone."), pause: .focused) }
                    sample("Grip hover") { GripHandle(forcedHover: true).padding(Space.sm).background(Ink.barGround) }
                }
                VStack(alignment: .leading, spacing: Space.lg) {
                    sample("Meeting detected, app named") {
                        MeetingPrompt(appName: "Callbox", record: {}, notNow: {}).padding(Space.sm)
                    }
                    sample("Microphone in use, no app") {
                        MeetingPrompt(appName: nil, record: {}, notNow: {}).padding(Space.sm)
                    }
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
                            NoticeBanner(message: "Audio lost. Couldn't restart the microphone.", actionTitle: "Retry",
                                         action: {})
                        }
                        .frame(width: 360)
                    }
                }
            }
            .padding(Space.lg)
            .background(Ink.canvas, in: RoundedRectangle(cornerRadius: Metric.rowCorner))
            .overlay(RoundedRectangle(cornerRadius: Metric.rowCorner).strokeBorder(Ink.divider, lineWidth: Metric.hairline))
        }
    }

    /// The controls with room around them for the shadow, which the panel's margin gives
    /// them in life.
    private func bar(_ status: RecordingControls.Status, callAudioDown: String? = nil, meter: LevelMeter = RecordingGallery.meter,
                     pause: BarButtonLook? = nil, stop: BarButtonLook? = nil, reduceMotion: Bool = false) -> some View {
        RecordingControls(status: status, callAudioDown: callAudioDown, meter: meter, pauseLook: pause, stopLook: stop,
                          reduceMotion: reduceMotion)
            .padding(Space.sm)
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
