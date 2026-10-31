import SwiftUI

/// Status shown for an assistant reply that has not produced its first token yet.
///
/// The progress bar is driven only by numbers the engine actually reported - the `prefill`
/// events built from Strata's live `prompt_read` / `prompt_total`. When those stats never
/// arrive (engine reports no progress, request queued behind another, non-Strata backend)
/// there is no bar and no invented percentage: just the wave with a plain "Prefilling" label.
public struct PrefillProgressView: View {
    private let message: ChatMessage

    public init(message: ChatMessage) {
        self.message = message
    }

    private var total: Int? {
        guard let t = message.prefillTotal, t > 0 else { return nil }
        return t
    }

    private var read: Int {
        guard let total = total else { return 0 }
        return min(max(message.prefillRead ?? 0, 0), total)
    }

    private var fraction: Double {
        guard let total = total, total > 0 else { return 0 }
        return Double(read) / Double(total)
    }

    public var body: some View {
        if total != nil {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Prefilling")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer(minLength: 8)
                    if let rate = message.prefillTokS, rate > 0 {
                        Text("\(Int(rate)) tok/s")
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    Text("\(Int(fraction * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(hex: "7c5cff"))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                        Capsule()
                            .fill(Color(hex: "7c5cff"))
                            .frame(width: max(4, geo.size.width * CGFloat(fraction)))
                    }
                }
                .frame(height: 6)
                // The engine reports progress once per prefill chunk, so the real numbers arrive as
                // steps. This only glides between samples the engine actually sent - it never draws a
                // position the engine did not report.
                .animation(.linear(duration: 1.2), value: fraction)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TypingWaveIndicatorView(statusText: message.phase ?? "Prefilling")
        }
    }
}
