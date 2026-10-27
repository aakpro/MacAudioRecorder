import SwiftUI
import InternalSoundRecorderCore

public struct AudioWaveformView: View {
    public let levels: AudioLevels
    public let isRecording: Bool

    private let barCount = 18

    public init(levels: AudioLevels, isRecording: Bool) {
        self.levels = levels
        self.isRecording = isRecording
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                barView(index: index)
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.15))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func barView(index: Int) -> some View {
        let heightMultiplier = computeBarHeight(for: index)
        let barHeight = max(4.0, CGFloat(heightMultiplier) * 32.0)

        RoundedRectangle(cornerRadius: 2)
            .fill(barColor(for: heightMultiplier))
            .frame(width: 4, height: isRecording ? barHeight : 4)
            .animation(.easeInOut(duration: 0.08), value: heightMultiplier)
    }

    private func computeBarHeight(for index: Int) -> Float {
        guard isRecording else { return 0.0 }
        // Center-weighted distribution with dynamic variance
        let normalizedIndex = Float(index) / Float(barCount - 1)
        let centerDistance = abs(normalizedIndex - 0.5) * 2.0
        let bellShape = 1.0 - (centerDistance * 0.4)

        // Slight simulated frequency differentiation based on RMS and Peak
        let variance = sin(Float(index) * 1.5 + levels.rms * 10.0) * 0.15
        let base = (levels.rms * 0.7) + (levels.peak * 0.3)
        let result = (base * bellShape) + variance
        return min(1.0, max(0.05, result))
    }

    private func barColor(for height: Float) -> Color {
        guard isRecording else { return Color.gray.opacity(0.4) }
        if height > 0.85 {
            return Color.red
        } else if height > 0.65 {
            return Color.yellow
        } else {
            return Color.green
        }
    }
}
