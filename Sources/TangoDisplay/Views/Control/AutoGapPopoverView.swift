import SwiftUI

struct AutoGapPopoverView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 10) {
            Text("Auto-gap")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(settings.autoGapDuration, specifier: "%.1f") s")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(height: 14)

            Slider(value: $settings.autoGapDuration, in: 0.5...5, step: 0.5)
        }
        .padding(12)
        .frame(width: 200)
    }
}
