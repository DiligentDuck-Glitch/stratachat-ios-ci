import SwiftUI

public struct ClaudeActionToolbar: View {
    let message: ChatMessage
    let onRegenerate: () -> Void
    let onPerformance: (ChatMessage) -> Void
    
    @State private var copied: Bool = false
    @State private var showShareSheet: Bool = false
    
    public init(message: ChatMessage, onRegenerate: @escaping () -> Void = {},
                onPerformance: @escaping (ChatMessage) -> Void = { _ in }) {
        self.message = message
        self.onRegenerate = onRegenerate
        self.onPerformance = onPerformance
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            // Speedometer pill
            let effectiveTps = message.meta?.tps ?? {
                guard let meta = message.meta, let tok = meta.tokens, let el = meta.elapsed, el > 0 else { return nil }
                return Double(tok) / el
            }()
            
            if let tps = effectiveTps, tps > 0 {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onPerformance(message)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.needle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "ffd60a"))
                        
                        Text(String(format: "%.1f tok/s", tps))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
            }
            
            // Action buttons - visible once message is done
            if message.status != "streaming" && !message.content.isEmpty {
                // Copy button
                Button {
                    UIPasteboard.general.string = message.content
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        if copied {
                            Text("Copied")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .foregroundColor(copied ? Color.green : .white.opacity(0.45))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Capsule())
                }
                
                // Regenerate button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onRegenerate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Capsule())
                }
                
                // Share button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    shareMessage()
                } label: {
                    Image(systemName: "square.arrow.up")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Capsule())
                }
            }
            
            Spacer()
        }
        .padding(.top, 4)
    }
    
    private func shareMessage() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }
        let activityVC = UIActivityViewController(activityItems: [message.content], applicationActivities: nil)
        rootVC.present(activityVC, animated: true)
    }
}
