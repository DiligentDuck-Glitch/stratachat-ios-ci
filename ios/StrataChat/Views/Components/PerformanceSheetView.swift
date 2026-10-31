import SwiftUI

/// PC performance inspector. One ring in the top bar opens this sheet: thermals, watts,
/// rails, memory pressure, fans, the power profile the desktop actually has active, and
/// context. A sensor the hardware does not expose prints a dash, never a guess.
public struct PerformanceSheetView: View {
    @ObservedObject var chatVM: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    // Both halves read the view model's single poller, so the ring and the sheet can never disagree.
    private var hw: HardwareInfo? { chatVM.pcHardware }
    private var errorMessage: String? { chatVM.pcHardwareError }

    public init(chatVM: ChatViewModel) {
        self.chatVM = chatVM
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    inferenceSection
                    powerSection
                    thermalSection
                    memorySection
                    boardSection
                    contextSection
                    notesSection
                }
                .padding(16)
            }
            .navigationTitle("Performance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
            }
            .task { await chatVM.refreshPCHardwareNow() }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerCard: some View {
        HStack {
            Image(systemName: "waveform.path.ecg")
                .foregroundColor(Color(hex: "00f2fe"))
            Text("PC TELEMETRY")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            if let profile = hw?.powerProfile {
                Text(profile)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(profileColor(profile))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Inference for the reply this sheet was opened from

    // Opened from a reply's speed pill, that reply's metrics are shown. Opened from the top-bar ring,
    // the newest reply that carries metrics is, so neither half of the sheet is ever a wall of dashes.
    private var inferenceMessage: ChatMessage? {
        if let picked = chatVM.performanceMessage { return picked }
        for msg in chatVM.messages.reversed() {
            if msg.role == "assistant", msg.meta != nil { return msg }
        }
        return nil
    }

    @ViewBuilder
    private var inferenceSection: some View {
        sectionCard(title: "INFERENCE", symbol: "gauge.with.needle.fill") {
            if let meta = inferenceMessage?.meta {
                heroSpeed(meta)
                row("Reply", replyTime(inferenceMessage?.created))
                row("Model", meta.model ?? "—")
                row("Variant", meta.variant ?? "—")
                row("Generated", meta.tokens.map { "\($0) tok" } ?? "—")
                row("Prompt", meta.promptTokens.map { "\($0) tok" } ?? "—")
                row("Turn context", meta.contextUsed.map { "\($0) tok" } ?? "—")
                row("First token", fmtS(meta.ttft))
                row("Thinking", fmtS(meta.thoughtS))
                row("Elapsed", fmtS(meta.elapsed))
                row("Finish", meta.finishReason ?? "—")
            } else {
                keyLine("No inference metrics on this reply yet.")
            }
        }
    }

    @ViewBuilder
    private func heroSpeed(_ meta: MessageMeta) -> some View {
        let tps = meta.tps ?? speedOf(meta)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(tps.map { String(format: "%.1f", $0) } ?? "—")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "ffd60a"))
            Text("tok/s")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
            Spacer()
        }
        .padding(.bottom, 2)
    }

    private func speedOf(_ meta: MessageMeta) -> Double? {
        guard let tok = meta.tokens, let el = meta.elapsed, el > 0 else { return nil }
        return Double(tok) / el
    }

    private func fmtS(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.2f s", v)
    }

    private func replyTime(_ created: Double?) -> String {
        guard let created else { return "—" }
        return DateFormatter.localizedString(from: Date(timeIntervalSince1970: created),
                                             dateStyle: .none, timeStyle: .short)
    }

    // MARK: - Power

    @ViewBuilder
    private var powerSection: some View {
        sectionCard(title: "POWER", symbol: "bolt.fill") {
            row("CPU package", fmtW(hw?.cpuPackageW))
            ForEach(Array((hw?.gpus ?? []).enumerated()), id: \.offset) { _, g in
                row(shortGPUName(g), wattsLine(g))
            }
            railsRow
        }
    }

    @ViewBuilder
    private var railsRow: some View {
        if let rails = hw?.board?.railsV, !rails.isEmpty {
            keyLine(railLine(rails))
        } else {
            row("Rails", "—")
        }
    }

    private func railLine(_ rails: [String: Double]) -> String {
        Array(rails.keys).sorted()
            .map { "\($0) \(String(format: "%.2f", rails[$0] ?? 0))V" }
            .joined(separator: "  ")
    }

    // MARK: - Thermals

    @ViewBuilder
    private var thermalSection: some View {
        sectionCard(title: "THERMALS", symbol: "thermometer.medium") {
            ForEach(Array((hw?.gpus ?? []).enumerated()), id: \.offset) { _, g in
                gpuThermalRow(g)
            }
            row("CPU (Tctl)", fmtC(hw?.cpu?.tempC))
            row("CPU hot spot (Tccd1)", fmtC(hw?.cpu?.ccdC))
            row("Board system", fmtC(hw?.board?.systemC))
            row("VRM MOS", fmtC(hw?.board?.vrmMosC))
            row("Chipset", fmtC(hw?.board?.pchC))
        }
    }

    @ViewBuilder
    private func gpuThermalRow(_ g: HardwareGPUInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(shortGPUName(g))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(fmtC(g.tempC))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(tempColor(g.tempC))
            }
            Text(gpuDetailLine(g))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private func gpuDetailLine(_ g: HardwareGPUInfo) -> String {
        "\(intPct(g.utilPct)) util · \(intPct(g.vramUtilPct)) vram · "
        + "\(intMib(g.vramUsedMib))/\(intMib(g.vramTotalMib)) · "
        + "\(intMhz(g.clockMhz))/\(intMhz(g.clockMaxMhz)) MHz · \(g.pstate ?? "—")"
    }

    // MARK: - Memory

    @ViewBuilder
    private var memorySection: some View {
        sectionCard(title: "MEMORY", symbol: "memorychip") {
            row("Used", memoryUsedLine)
            row("Available", intMib(hw?.memory?.availableMib))
            row("Swap", swapLine)
            row("Load 1m / 5m / 15m", loadLine)
        }
    }

    private var memoryUsedLine: String {
        guard let m = hw?.memory else { return "—" }
        return "\(intPct(m.usedPct)) · \(intMib(m.usedMib))/\(intMib(m.totalMib)) MiB"
    }

    private var swapLine: String {
        guard let m = hw?.memory else { return "—" }
        return "\(intMib(m.swapUsedMib))/\(intMib(m.swapTotalMib)) MiB"
    }

    private var loadLine: String {
        guard let c = hw?.cpu else { return "—" }
        return String(format: "%.2f / %.2f / %.2f", c.load1m ?? 0, c.load5m ?? 0, c.load15m ?? 0)
    }

    // MARK: - Fans

    @ViewBuilder
    private var boardSection: some View {
        sectionCard(title: "FANS", symbol: "fan") {
            if let fans = hw?.board?.fansRpm, !fans.isEmpty {
                ForEach(Array(fans.keys.sorted()), id: \.self) { key in
                    row(key, fanLine(fans, key))
                }
            } else {
                row("Tach sources", "none readable")
            }
        }
    }

    private func fanLine(_ fans: [String: Double], _ key: String) -> String {
        "\(Int(fans[key] ?? 0)) RPM"
    }

    // MARK: - Context

    @ViewBuilder
    private var contextSection: some View {
        sectionCard(title: "CONTEXT", symbol: "circle.dashed") {
            row("Session used", contextLine)
        }
    }

    private var contextLine: String {
        let used = chatVM.currentContextTokens
        let cap = max(1, chatVM.maxContextTokens)
        let pct = Int((Double(used) / Double(cap) * 100).rounded())
        return "\(used) / \(cap) tokens (\(pct)%)"
    }

    // MARK: - Unsupported, stated plainly

    @ViewBuilder
    private var notesSection: some View {
        if let missing = hw?.unsupported, !missing.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("NOT AVAILABLE ON THIS PC")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
                Text(unsupportedLine(missing))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Text("This machine is air cooled — no loop sensor, no flow meter, no DRAM thermistor.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 12))
                .foregroundColor(.orange)
        }
    }

    private func unsupportedLine(_ missing: [String]) -> String {
        missing.map { $0.replacingOccurrences(of: "_", with: " ") }.joined(separator: " · ")
    }

    // MARK: - Shared card chrome

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, symbol: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "c9b8ff"))
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.92))
                .multilineTextAlignment(.trailing)
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func keyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white.opacity(0.6))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    // MARK: - Formatting. A missing sensor is always a dash, never a number.

    private func fmtC(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.1f °C", v)
    }

    private func fmtW(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.1f W", v)
    }

    private func intPct(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()))%"
    }

    private func intMib(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()))"
    }

    private func intMhz(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()))"
    }

    private func wattsLine(_ g: HardwareGPUInfo) -> String {
        let w = fmtW(g.powerW)
        guard let limit = g.powerLimitW else { return w }
        return "\(w) / \(Int(limit)) W cap"
    }

    private func shortGPUName(_ g: HardwareGPUInfo) -> String {
        let n = g.name ?? "GPU"
        if n.contains("5070") { return "5070 Ti (model)" }
        if n.contains("3070") { return "3070 (vision)" }
        return n
    }

    private func tempColor(_ v: Double?) -> Color {
        guard let v else { return .white.opacity(0.4) }
        if v < 55 { return Color(hex: "34d399") }
        if v <= 70 { return Color(hex: "fbbf24") }
        return Color(hex: "f87171")
    }

    private func profileColor(_ profile: String) -> Color {
        switch profile {
        case "power-saver": return Color(hex: "60a5fa")
        case "performance": return Color(hex: "34d399")
        default: return Color(hex: "fbbf24")
        }
    }
}
