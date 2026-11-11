import SwiftUI

/// A thin bar that fills from the leading edge as work gets done: an `Ink.divider` track
/// and an `Ink.accent` fill, 4 tall with round ends. `value` runs from 0 to 1. VoiceOver
/// reads `label` and the percent.
struct KitProgressBar: View {
    let value: Double
    let label: String

    private var fraction: Double { min(max(value, 0), 1) }

    var body: some View {
        Capsule()
            .fill(Ink.divider)
            .frame(width: Metric.progressBarWidth, height: Metric.progressBarHeight)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Ink.accent)
                    .frame(width: max(Metric.progressBarWidth * fraction, fraction > 0 ? Metric.progressBarHeight : 0))
            }
            .animation(Motion.level, value: fraction)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

extension Metric {
    static let progressBarWidth: CGFloat = 96
    static let progressBarHeight: CGFloat = 4
}
