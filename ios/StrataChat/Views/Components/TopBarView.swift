import SwiftUI
import Combine

public struct TopBarView: View {
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var statusVM: StatusViewModel
    @ObservedObject private var localEngine = LocalInferenceEngine.shared
    @State private var showRamHUD: Bool = false
    // PC telemetry is polled once by ChatViewModel on a 1 s loop shared with the Performance sheet.
    // Nothing is polled here: a Timer.publish owned by a View struct is rebuilt on every re-render and
    // never reaches its fire date, which is why this ring used to sit on "?" forever.
    
    public init(chatVM: ChatViewModel, statusVM: StatusViewModel) {
        self.chatVM = chatVM
        self.statusVM = statusVM
    }
    
    private var stateColor: Color {
        if chatVM.backend == .local {
            return Color(hex: "00f2fe")
        }
        if chatVM.isWakingPC {
            return Color.yellow
        }
        guard statusVM.isOnline, let st = statusVM.status?.state else {
            return Color.gray
        }
        switch st {
        case "ready": return Color.green
        case "loading", "switching": return Color.yellow
        case "sleeping": return Color.blue
        default: return Color.gray
        }
    }
    
    private var modelTitle: String {
        if chatVM.backend == .local {
            if let active = localEngine.activeModel {
                let name = active.name
                if name.localizedCaseInsensitiveContains("iq3") {
                    return "MiniCPM-V · IQ3"
                } else if name.localizedCaseInsensitiveContains("q4") {
                    return "MiniCPM-V · Q4"
                } else if name.localizedCaseInsensitiveContains("2.6") {
                    return "MiniCPM-V 2.6"
                } else {
                    return "\(name) · Local"
                }
            }
            return "MiniCPM-V · On-Device"
        }
        if chatVM.isWakingPC {
            return "Waking PC..."
        }
        if !statusVM.isOnline {
            return "PC Asleep / Offline"
        }
        var chatVariant: String? = nil
        if let lastAssistant = chatVM.messages.last(where: { $0.role == "assistant" && $0.meta?.variant != nil }) {
            chatVariant = lastAssistant.meta?.variant
        }
        let variantName = chatVariant ?? statusVM.status?.variantDisplay ?? "Original GSQ 262k"
        if chatVM.backend == .hermes {
            return "Hermes · \(variantName)"
        } else {
            return "Strata · \(variantName)"
        }
    }
    
    private var statusBadgeText: String? {
        if chatVM.isWakingPC {
            return "Waking..."
        }
        guard let st = statusVM.status?.state else { return nil }
        if st == "loading" {
            return "Warming \(statusVM.elapsedSeconds)s"
        } else if st == "switching" {
            return "Switching \(statusVM.elapsedSeconds)s"
        }
        return nil
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            topBarRow
            
            if showRamHUD && chatVM.backend == .local {
                ramInlineHUDCard
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    ))
            }
        }
        .background(
            LinearGradient(
                colors: [Color(hex: "09090f"), Color(hex: "09090f").opacity(0.85), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .sheet(isPresented: $chatVM.showContextSheet) {
            ContextBreakdownSheet(chatVM: chatVM)
        }
        .sheet(isPresented: $chatVM.showPerformanceSheet) {
            PerformanceSheetView(chatVM: chatVM)
        }
    }
    
    @ViewBuilder
    private var topBarRow: some View {
        HStack(spacing: 10) {
            // Left menu button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    chatVM.drawerDragOffset = 0
                    chatVM.isDraggingDrawer = false
                    chatVM.showDrawer.toggle()
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
            }
            
            Spacer()
            
            // Center model / status capsule
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                chatVM.showModelPicker = true
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: stateColor.opacity(0.8), radius: 4)
                    
                    Text(modelTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if E2EEManager.shared.isEnabled {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    }
                    
                    if let badge = statusBadgeText {
                        Text(badge)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.yellow)
                    } else {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
            }
            
            Spacer()
            
            // Right capsule: RAM Ring (Local only) + Context Ring + New Chat
            HStack(spacing: 2) {
                if chatVM.backend == .local {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        localEngine.updateMemoryMetrics()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            showRamHUD.toggle()
                        }
                    } label: {
                        RamRingGaugeView(
                            usedBytes: localEngine.residentMemoryBytes,
                            maxBytes: localEngine.jetsamLimitBytes
                        )
                        .frame(width: 32, height: 32)
                    }
                    
                    Divider()
                        .frame(width: 1, height: 16)
                        .background(Color.white.opacity(0.2))
                }
                
                if chatVM.backend != .local {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        chatVM.performanceMessage = nil
                        chatVM.showPerformanceSheet = true
                    } label: {
                        TempRingGaugeView(cpuTempC: chatVM.pcHardware?.cpu?.tempC,
                                          gpuTempC: chatVM.pcHardware?.primaryGPU?.tempC)
                            .frame(width: 34, height: 34)
                    }

                    Divider()
                        .frame(width: 1, height: 16)
                        .background(Color.white.opacity(0.2))
                }

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    chatVM.showContextSheet = true
                } label: {
                    ContextRingGaugeView(ratio: chatVM.contextRatio)
                        .frame(width: 32, height: 32)
                }
                
                Divider()
                    .frame(width: 1, height: 16)
                    .background(Color.white.opacity(0.2))
                
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    chatVM.newChat()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 38)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
    
    // MARK: - Subview: Inline RAM HUD Card (No Modal / No New Window)
    @ViewBuilder
    private var ramInlineHUDCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(localEngine.isModelLoadedInMemory ? Color(hex: "00f2fe") : Color.gray)
                        .frame(width: 7, height: 7)
                        .shadow(color: (localEngine.isModelLoadedInMemory ? Color(hex: "00f2fe") : Color.clear).opacity(0.8), radius: 3)
                    Text("APPLE A19 PRO UNIFIED MEMORY")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        showRamHUD = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            
            // Active Model Chip
            if let active = localEngine.activeModel {
                HStack(spacing: 6) {
                    Image(systemName: "cpu")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "00f2fe"))
                    Text(active.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(localEngine.estimatedVRAMCacheString(for: localEngine.moeCacheWindowC))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "34d399"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Memory Bar & Numbers
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(localEngine.formattedMemoryString(localEngine.residentMemoryBytes) + " Resident")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Ceiling: " + localEngine.formattedMemoryString(localEngine.jetsamLimitBytes) + " (\(Int(localEngine.ramUsageRatio * 100))%)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 6)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "00f2fe"),
                                        localEngine.ramUsageRatio > 0.85 ? Color(hex: "ff453a") : (localEngine.ramUsageRatio > 0.65 ? Color(hex: "ffd60a") : Color(hex: "34d399"))
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(6, geo.size.width * CGFloat(localEngine.ramUsageRatio)), height: 6)
                    }
                }
                .frame(height: 6)
            }
            .padding(10)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            // Model State & Matrix Load / Unload Control
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Metal Unified Buffer & Expert Cache")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Text(localEngine.isModelLoadedInMemory
                         ? "● Pinned in VRAM (\(localEngine.formattedMemoryString(localEngine.metalAllocatedBytes)) Metal)"
                         : "○ Standby (0 MB Allocated)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(localEngine.isModelLoadedInMemory ? Color(hex: "00f2fe") : .white.opacity(0.6))
                }
                
                Spacer()
                
                if localEngine.isModelLoadedInMemory {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        localEngine.unloadActiveModel()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "eject.fill")
                                .font(.system(size: 11))
                            Text("Unload VRAM")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "ff453a"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: "ff453a").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        localEngine.preloadActiveModel()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11))
                            Text("Preheat VRAM")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: "00f2fe"))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal, 4)
            
            // Active pipeline pills
            HStack(spacing: 5) {
                Text("CTX: \(localEngine.contextLength / 1024)K (\(localEngine.kvCacheQuant.uppercased()))")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(Color(hex: "34d399"))
                    .clipShape(Capsule())
                
                Text("VRAM: c=\(localEngine.lastResolvedWindowC)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(Color(hex: "00f2fe"))
                    .clipShape(Capsule())
                
                if let hit = localEngine.lastMoECacheHitRate {
                    Text(String(format: "MoE %.0f%%", hit))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(hex: "34d399").opacity(0.18))
                        .foregroundColor(Color(hex: "34d399"))
                        .clipShape(Capsule())
                }
                
                if let accept = localEngine.lastDSparkAcceptanceRate {
                    Text(String(format: "DSpark %.0f%%", accept))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(hex: "ffd60a").opacity(0.18))
                        .foregroundColor(Color(hex: "ffd60a"))
                        .clipShape(Capsule())
                } else if localEngine.isUncensoredLoRAEnabled && localEngine.isLoRADownloaded {
                    Text("Uncensored")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(hex: "ffd60a").opacity(0.15))
                        .foregroundColor(Color(hex: "ffd60a"))
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                Text("p8d8 · d=\(localEngine.moeLookaheadDepth)")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "12121d"))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "00f2fe").opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 14, x: 0, y: 8)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}
