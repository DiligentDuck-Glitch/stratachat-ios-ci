import SwiftUI

public struct ContextBreakdownSheet: View {
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject private var localEngine = LocalInferenceEngine.shared
    @Environment(\.dismiss) private var dismiss
    
    public init(chatVM: ChatViewModel) {
        self.chatVM = chatVM
    }
    
    private var gaugeColor: Color {
        if chatVM.contextRatio < 0.50 {
            return Color(hex: "7c5cff")
        } else if chatVM.contextRatio < 0.80 {
            return Color(hex: "ffd60a")
        } else {
            return Color(hex: "ff453a")
        }
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "0d0e17")
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Hero Ring & Usage Card
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "circle.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(gaugeColor)
                                
                                Text("Context Window & Budget")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Text("\(max(1, chatVM.maxContextTokens / 1024))K Window")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: "7c5cff"))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: "7c5cff").opacity(0.16))
                                    .clipShape(Capsule())
                            }
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            HStack(spacing: 20) {
                                // Large Circular Ring
                                ZStack {
                                    Circle()
                                        .stroke(Color.white.opacity(0.1), lineWidth: 8)
                                    Circle()
                                        .trim(from: 0.0, to: max(0.04, CGFloat(min(1.0, chatVM.contextRatio))))
                                        .stroke(gaugeColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                        .animation(.easeInOut(duration: 0.4), value: chatVM.contextRatio)
                                    
                                    VStack(spacing: 2) {
                                        Text(String(format: "%.1f%%", chatVM.contextRatio * 100.0))
                                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                                            .foregroundColor(.white)
                                        Text("Filled")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                }
                                .frame(width: 84, height: 84)
                                
                                // Token Counts
                                VStack(alignment: .leading, spacing: 6) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("ACTIVE CONTEXT")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white.opacity(0.45))
                                        Text("\(chatVM.currentContextTokens.formatted()) tokens")
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("REMAINING HEADROOM")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white.opacity(0.45))
                                        Text("\(max(0, chatVM.maxContextTokens - chatVM.currentContextTokens).formatted()) tokens")
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundColor(.green)
                                    }
                                }
                                
                                Spacer()
                            }
                            
                            if chatVM.backend == .local {
                                Divider().background(Color.white.opacity(0.1))
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("ON-DEVICE CONTEXT SIZE")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white.opacity(0.5))
                                        Spacer()
                                        let kvMB = (localEngine.contextLength * 20) / 1024
                                        Text("KV Cache: ~\(kvMB) MB RAM")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(Color(hex: "00f2fe"))
                                    }
                                    
                                    HStack(spacing: 8) {
                                        ForEach([2048, 4096, 8192, 16384], id: \.self) { ctx in
                                            let selected = (localEngine.contextLength == ctx)
                                            Button {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                localEngine.contextLength = ctx
                                            } label: {
                                                Text("\(ctx / 1024)K")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 7)
                                                    .background(selected ? Color(hex: "00f2fe") : Color.white.opacity(0.06))
                                                    .foregroundColor(selected ? .black : .white)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(18)
                        .background(Color(hex: "171826"))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        
                        // KV Cache & Performance Grid
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CACHE & REUSE METRICS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.45))
                                .padding(.horizontal, 4)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                MetricCard(
                                    title: "Reused KV Tokens",
                                    value: "\(chatVM.cachedTokens.formatted()) tok",
                                    icon: "bolt.fill",
                                    color: Color(hex: "00f0ff")
                                )
                                
                                let hitRate = chatVM.currentContextTokens > 0 ? Double(chatVM.cachedTokens) / Double(chatVM.currentContextTokens) * 100.0 : 0.0
                                MetricCard(
                                    title: "KV Cache Hit Rate",
                                    value: String(format: "%.1f%%", min(100.0, max(0.0, hitRate))),
                                    icon: "speedometer",
                                    color: Color(hex: "ffd60a")
                                )
                                
                                MetricCard(
                                    title: "Active Backend",
                                    value: chatVM.backend.displayName,
                                    icon: "server.rack",
                                    color: Color(hex: "b892ff")
                                )
                                
                                MetricCard(
                                    title: "Total Capacity",
                                    value: "\(chatVM.maxContextTokens.formatted()) tok",
                                    icon: "memorychip",
                                    color: Color.green
                                )
                            }
                        }
                        
                        // Action Button: Compact or Clear Context
                        if chatVM.backend == .local {
                            VStack(spacing: 8) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    localEngine.resetLocalSessionContext()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 15, weight: .bold))
                                        Text("Reset KV Cache Session")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(hex: "00f2fe"))
                                    .foregroundColor(.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                
                                Text("Clears the on-device KV cache in Metal VRAM while keeping your chat messages visible.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.45))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 10)
                            }
                            .padding(.top, 10)
                        } else {
                            VStack(spacing: 8) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    dismiss()
                                    chatVM.compactChat()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                                            .font(.system(size: 15, weight: .bold))
                                        Text("Compact Conversation Context (/compact)")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(hex: "7c5cff"))
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .shadow(color: Color(hex: "7c5cff").opacity(0.35), radius: 8, x: 0, y: 4)
                                }
                                
                                Text("Summarizes earlier turns to free up tokens while retaining key context and rules.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.45))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 10)
                            }
                            .padding(.top, 10)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Context Inspector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "7c5cff"))
                }
            }
        }
    }
}
