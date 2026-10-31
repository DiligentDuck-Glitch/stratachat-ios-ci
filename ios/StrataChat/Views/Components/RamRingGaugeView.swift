import SwiftUI

public struct RamRingGaugeView: View {
    public let usedBytes: UInt64
    public let maxBytes: UInt64
    
    public init(usedBytes: UInt64, maxBytes: UInt64) {
        self.usedBytes = usedBytes
        self.maxBytes = maxBytes
    }
    
    private var ratio: Double {
        guard maxBytes > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(usedBytes) / Double(maxBytes)))
    }
    
    private var gaugeColor: Color {
        if ratio < 0.60 {
            return Color(hex: "00f2fe") // Cyan / Electric blue
        } else if ratio < 0.85 {
            return Color(hex: "ffd60a") // Warm amber
        } else {
            return Color(hex: "ff453a") // Alert red
        }
    }
    
    private var percentageText: String {
        let pct = Int(ratio * 100.0)
        return "\(pct)"
    }
    
    public var body: some View {
        ZStack {
            // Track circle
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 2.2)
            
            // Progress stroke
            Circle()
                .trim(from: 0.0, to: max(0.05, CGFloat(min(1.0, ratio))))
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "00f2fe"), gaugeColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.35), value: ratio)
            
            // Center indicator
            if ratio >= 0.05 {
                Text(percentageText)
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
            } else {
                Image(systemName: "memorychip")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(hex: "00f2fe"))
            }
        }
        .frame(width: 22, height: 22)
    }
}
