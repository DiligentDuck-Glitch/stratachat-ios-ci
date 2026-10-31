import SwiftUI

public struct TypingWaveIndicatorView: View {
    let statusText: String?
    
    @State private var phase: CGFloat = 0.0
    
    public init(statusText: String? = nil) {
        self.statusText = statusText
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            // 3 undulating sinusoidal dots
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color(hex: "7c5cff"))
                        .frame(width: 7, height: 7)
                        .scaleEffect(scale(for: i))
                        .opacity(opacity(for: i))
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            
            // Dynamic status label
            if let st = statusText, !st.isEmpty {
                Text(st)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .transition(.opacity)
            } else {
                Text("Prefilling…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                phase = 1.0
            }
        }
    }
    
    private func scale(for index: Int) -> CGFloat {
        let offset = Double(index) * 0.35
        let progress = Double(phase)
        let val = sin((progress + offset) * .pi)
        return CGFloat(0.7 + (val * 0.5))
    }
    
    private func opacity(for index: Int) -> Double {
        let offset = Double(index) * 0.35
        let progress = Double(phase)
        let val = sin((progress + offset) * .pi)
        return 0.4 + (val * 0.6)
    }
}
