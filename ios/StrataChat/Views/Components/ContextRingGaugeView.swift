import SwiftUI

public struct ContextRingGaugeView: View {
    public let ratio: Double // 0.0 to 1.0
    
    public init(ratio: Double) {
        self.ratio = ratio
    }
    
    private var gaugeColor: Color {
        if ratio < 0.50 {
            return Color(hex: "7c5cff") // Electric purple / cyan
        } else if ratio < 0.80 {
            return Color(hex: "ffd60a") // Warm amber
        } else {
            return Color(hex: "ff453a") // Urgent coral red
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
                .stroke(gaugeColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.35), value: ratio)
            
            // Center indicator
            if ratio >= 0.01 {
                Text(percentageText)
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            } else {
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 3.5, height: 3.5)
            }
        }
        .frame(width: 22, height: 22)
    }
}
