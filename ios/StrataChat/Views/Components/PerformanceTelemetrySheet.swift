import SwiftUI

public struct PerformanceTelemetrySheet: View {
    let meta: MessageMeta
    @Environment(\.dismiss) private var dismiss
    
    public init(meta: MessageMeta) {
        self.meta = meta
    }
    
    private var effectiveTps: Double {
        if let tps = meta.tps, tps > 0 { return tps }
        if let tok = meta.tokens, let el = meta.elapsed, el > 0 {
            return Double(tok) / el
        }
        return 0.0
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "0d0e17")
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Speed Gauge Hero Card
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "gauge.with.needle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color(hex: "ffd60a"))
                                
                                Text("Inference Performance")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                if let variant = meta.variant {
                                    Text(variant)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(Color(hex: "7c5cff"))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(hex: "7c5cff").opacity(0.16))
                                        .clipShape(Capsule())
                                }
                            }
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                Text(String(format: "%.1f", effectiveTps))
                                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text("tok/s")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color(hex: "ffd60a"))
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Decode Throughput")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.5))
                                    Text("Active GPU Stream")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Color.green)
                                }
                            }
                        }
                        .padding(18)
                        .background(Color(hex: "171826"))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        
                        // Latency & Speed Grid
                        VStack(alignment: .leading, spacing: 12) {
                            Text("LATENCY & TIMINGS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.45))
                                .padding(.horizontal, 4)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                MetricCard(
                                    title: "Time to First Token (TTFT)",
                                    value: meta.ttft != nil ? String(format: "%.2f s", meta.ttft!) : "N/A",
                                    icon: "bolt.fill",
                                    color: Color(hex: "00f0ff")
                                )
                                
                                MetricCard(
                                    title: "Total Generation Time",
                                    value: meta.elapsed != nil ? String(format: "%.2f s", meta.elapsed!) : "N/A",
                                    icon: "clock.fill",
                                    color: Color(hex: "b892ff")
                                )
                                
                                MetricCard(
                                    title: "Reasoning Time",
                                    value: meta.thoughtS != nil ? String(format: "%.1f s", meta.thoughtS!) : "0.0 s",
                                    icon: "lightbulb.fill",
                                    color: Color(hex: "ffd60a")
                                )
                                
                                MetricCard(
                                    title: "Output Length",
                                    value: "\(meta.tokens ?? 0) tok",
                                    icon: "text.word.spacing",
                                    color: Color.green
                                )
                            }
                        }
                        
                        // Context & KV Cache Card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("CONTEXT & KV CACHE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.45))
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 12) {
                                DetailRow(label: "Prompt / Context Tokens", value: "\(meta.promptTokens ?? 0) tok")
                                DetailRow(label: "Cached KV Tokens", value: "\(meta.cachedTokens ?? 0) tok")
                                
                                if let cached = meta.cachedTokens, let prompt = meta.promptTokens, prompt > 0 {
                                    let hitRate = min(100.0, max(0.0, Double(cached) / Double(prompt) * 100.0))
                                    DetailRow(label: "KV Cache Hit Rate", value: String(format: "%.1f%%", hitRate), highlight: true)
                                }
                                
                                DetailRow(label: "Max Context Window", value: "262,144 tokens (262k)")
                            }
                            .padding(16)
                            .background(Color(hex: "171826"))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        }
                        
                        // Hardware & Engine Card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("HARDWARE & ENGINE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.45))
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 12) {
                                DetailRow(label: "Dedicated GPU", value: "NVIDIA RTX 5070 Ti (16GB)")
                                DetailRow(label: "Architecture", value: "Blackwell GB203, PCIe 4.0 x16")
                                DetailRow(label: "Inference Engine", value: "Strata 0.1.47 (GSQ Expert Cache)")
                                DetailRow(label: "Active Model", value: meta.model ?? "Qwen 3.8 Flash Next 262k")
                            }
                            .padding(16)
                            .background(Color(hex: "171826"))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Performance Telemetry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "7c5cff"))
                    .font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }
}

public struct MetricCard: View {
    public let title: String
    public let value: String
    public let icon: String
    public let color: Color
    
    public init(title: String, value: String, icon: String, color: Color) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
        }
        .padding(12)
        .background(Color(hex: "171826"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var highlight: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(highlight ? Color(hex: "ffd60a") : .white)
        }
    }
}
