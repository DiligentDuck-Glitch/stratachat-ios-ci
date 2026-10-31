import SwiftUI

/// Dual temperature ring for the top bar. The upper half-arc is the CPU package, the lower half-arc is
/// the GPU that actually runs the model. Each half fills 0-100 C on its own and is coloured from its own
/// reading, so a hot card beside a cool CPU reads as two different colours instead of one blended number.
///
/// `Circle().trim` starts at 3 o'clock and runs clockwise, so the top half is 0.5 -> 1.0 and the bottom
/// half is 0.0 -> 0.5. No rotation is needed. Each arc stops at 0.46 of the circle so the two halves keep
/// a visible gap at 3 and 9 o'clock instead of bleeding into one ring.
public struct TempRingGaugeView: View {
    public let cpuTempC: Double?
    public let gpuTempC: Double?

    private static let halfSpan: CGFloat = 0.46

    public init(cpuTempC: Double?, gpuTempC: Double?) {
        self.cpuTempC = cpuTempC
        self.gpuTempC = gpuTempC
    }

    private func gaugeColor(_ tempC: Double?) -> Color {
        guard let tempC else { return Color.white.opacity(0.30) }
        if tempC < 55 { return Color(hex: "34d399") }
        if tempC <= 70 { return Color(hex: "fbbf24") }
        return Color(hex: "ff453a")
    }

    private func frac(_ tempC: Double?) -> CGFloat {
        guard let tempC else { return 0 }
        return CGFloat(min(1.0, max(0.0, tempC / 100.0)))
    }

    private func numberText(_ tempC: Double?) -> String {
        guard let tempC else { return "?" }
        return "\(Int(tempC.rounded()))"
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 2.2)

            // CPU across the top, left to right.
            Circle()
                .trim(from: 0.5, to: 0.5 + max(0.04, Self.halfSpan * frac(cpuTempC)))
                .stroke(gaugeColor(cpuTempC), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .animation(.easeInOut(duration: 0.35), value: cpuTempC ?? 0)

            // GPU across the bottom, right to left.
            Circle()
                .trim(from: 0.0, to: max(0.04, Self.halfSpan * frac(gpuTempC)))
                .stroke(gaugeColor(gpuTempC), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .animation(.easeInOut(duration: 0.35), value: gpuTempC ?? 0)

            VStack(spacing: 3) {
                Text(numberText(cpuTempC))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(gaugeColor(cpuTempC))

                Rectangle()
                    .frame(width: 11, height: 0.6)
                    .foregroundColor(.white.opacity(0.18))

                Text(numberText(gpuTempC))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(gaugeColor(gpuTempC))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CPU \(numberText(cpuTempC)) degrees, GPU \(numberText(gpuTempC)) degrees")
    }
}
