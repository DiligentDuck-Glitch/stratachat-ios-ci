import SwiftUI

public struct HardwareSheetView: View {
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var statusVM: StatusViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showSleepAlert: Bool = false
    @State private var showShutdownAlert: Bool = false
    
    public init(chatVM: ChatViewModel, statusVM: StatusViewModel) {
        self.chatVM = chatVM
        self.statusVM = statusVM
    }
    
    private var gpuString: String {
        guard let gpu = statusVM.status?.gpu,
              let used = gpu.usedMib,
              let total = gpu.totalMib else {
            return "VRAM: 0 MB"
        }
        let usedGB = used / 1024.0
        let totalGB = total / 1024.0
        return String(format: "%.1f GB / %.1f GB", usedGB, totalGB)
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "09090f").ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 18) {
                        backendSection
                        if chatVM.backend == .local {
                            onDeviceSection
                        } else {
                            reasoningSection
                            architectureSection
                            contextSection
                            modelActionsSection
                        }
                        pcPowerSection
                        
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Model & Hardware")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "7c5cff"))
                }
            }
            .alert("Put PC to Sleep?", isPresented: $showSleepAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Sleep PC", role: .destructive) {
                    Task { await statusVM.sleepPC() }
                }
            } message: {
                Text("The PC will enter low-power sleep mode. You can wake it anytime via Wake-on-LAN or by sending a message on Wi-Fi.")
            }
            .alert("Shut Down PC?", isPresented: $showShutdownAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Shut Down", role: .destructive) {
                    Task { await statusVM.shutdownPC() }
                }
            } message: {
                Text("The PC will power off completely. Note: To wake from shutdown via Wake-on-LAN, ensure 'Resume By PCI-E Device' is enabled in your MSI B550 BIOS.")
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var backendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHAT BACKEND")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.5))
            
            Picker("Backend", selection: $chatVM.backend) {
                Text("Strata Direct").tag(Backend.strata)
                Text("Hermes Agent").tag(Backend.hermes)
                Text("On-Device").tag(Backend.local)
            }
            .pickerStyle(.segmented)
            
            Text(chatVM.backend == .local ? "Offline on-device MiniCPM-V 4.7 35B-A3B running locally on iPhone 17 Pro Metal" : (chatVM.backend == .hermes ? "Autonomous agent with tools, file ops & live execution" : "Direct low-latency LLM streaming from local GPU"))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .padding(.top, 2)
        }
        .padding(14)
        .background(Color(hex: "181826"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    @ViewBuilder
    private var onDeviceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "cpu.fill")
                    .foregroundColor(Color(hex: "00f2fe"))
                Text("IPHONE 17 PRO ON-DEVICE ENGINE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("Metal 3.2")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "00f2fe"))
            }
            
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Model")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                        Text("MiniCPM-V 4.7 (35B-A3B MoE)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text("3.5B Active")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "00f2fe").opacity(0.18))
                        .foregroundColor(Color(hex: "00f2fe"))
                        .clipShape(Capsule())
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Available Unified RAM")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                        Text(LocalInferenceEngine.shared.availableMemoryFormatted)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text("~9.5 GB Limit Entitlement")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "34d399"))
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Inference Pipeline")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                        Text("LES + 4-Bit KV + Persistent VRAM")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text(LocalInferenceEngine.shared.estimatedVRAMCacheString(for: LocalInferenceEngine.shared.moeCacheWindowC))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "34d399"))
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            NavigationLink(destination: LocalModelManagerContentView(isModalSheet: false)) {
                HStack {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 13))
                    Text("Manage Local Models & Parameters…")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black.opacity(0.6))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(Color(hex: "00f2fe"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(Color(hex: "181826"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // Where the current effort actually came from, stated plainly: this chat, the record Hermes
    // holds for it, or nothing at all.
    private var effortProvenance: String {
        if chatVM.effortOverride(forChat: chatVM.currentChatId) != nil {
            return "Chosen on this chat, on this phone."
        }
        if let lock = chatVM.hermesLock {
            if lock.locked, let recorded = lock.effort {
                return "Recorded by Hermes for this chat: \(recorded)."
            }
            return "Hermes holds no model lock for this chat - it was started on the PC - so this is the runtime default."
        }
        return "No effort recorded by Hermes for this chat yet."
    }

    @ViewBuilder
    private var reasoningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("REASONING EFFORT")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(chatVM.effortLevel.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "7c5cff"))
            }
            
            HStack(spacing: 6) {
                ForEach(EffortLevel.allCases) { level in
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        chatVM.setEffortLevel(level, forChat: chatVM.currentChatId)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: level.iconName)
                                .font(.system(size: 13, weight: .semibold))
                            Text(level.shortName)
                                .font(.system(size: 11, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(chatVM.effortLevel == level ? Color(hex: "7c5cff") : Color.white.opacity(0.06))
                        .foregroundColor(chatVM.effortLevel == level ? .white : .white.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            
            Text(effortProvenance)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))

            Text(chatVM.effortLevel == .off ? "Reasoning / thinking disabled for quick direct responses." : "Drives thinking depth and tool verification for \(chatVM.backend == .hermes ? "Hermes Agent" : "Strata Direct").")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.6))
                .padding(.top, 2)
        }
        .padding(14)
        .background(Color(hex: "181826"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    @ViewBuilder
    private var architectureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MODEL ARCHITECTURE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(chatVM.backend == .hermes ? "Powers Hermes Agent" : "Powers Strata Direct")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "7c5cff"))
            }
            
            HStack(spacing: 10) {
                let isSwift = (statusVM.status?.variant ?? "").starts(with: "swift") || statusVM.status?.variant == nil
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    chatVM.setPreferredVariant("swift", for: chatVM.backend)
                    if !isSwift {
                        Task { await statusVM.switchVariant("swift") }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Swift 1.5")
                                .font(.system(size: 14, weight: .bold))
                            if isSwift {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                            }
                        }
                        Text("Conversational · Anti-overthinking")
                            .font(.system(size: 11))
                            .opacity(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(isSwift ? Color(hex: "7c5cff") : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    chatVM.setPreferredVariant("original", for: chatVM.backend)
                    Task { await statusVM.switchVariant("original") }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Original GSQ")
                                .font(.system(size: 14, weight: .bold))
                            if statusVM.status?.variant == "original" {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                            }
                        }
                        Text("Deep reasoning monologues")
                            .font(.system(size: 11))
                            .opacity(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(statusVM.status?.variant == "original" ? Color(hex: "7c5cff") : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(14)
        .background(Color(hex: "181826"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    @ViewBuilder
    private var contextSection: some View {
        let active = statusVM.switchingToVariant ?? statusVM.status?.variant ?? "swift"
        
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CONTEXT WINDOW & SPEED (RTX 5070 Ti)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                if let switching = statusVM.switchingToVariant {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.65)
                        Text("Switching to \(switching)...")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "ffd60a"))
                    }
                } else {
                    Text(statusVM.status?.variantDisplay ?? "Swift 1.5")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "7c5cff"))
                }
            }
            
            VStack(spacing: 8) {
                // 64k Option
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    chatVM.configuredMaxContext = 65536
                    UserDefaults.standard.set(65536, forKey: "strata_active_context_limit")
                    chatVM.setPreferredVariant("swift-64k", for: chatVM.backend)
                    Task { await statusVM.switchVariant("swift-64k") }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("64k Ultra-Fast")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                Text("~90 tok/s")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(hex: "34c759"))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color(hex: "34c759").opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            Text("4-bit KV · 8.8 GB GPU VRAM · Lowest latency voice")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        if active == "swift-64k" {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(hex: "7c5cff"))
                                .font(.system(size: 16))
                        }
                    }
                    .padding(12)
                    .background(active == "swift-64k" ? Color(hex: "7c5cff").opacity(0.18) : Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(active == "swift-64k" ? Color(hex: "7c5cff").opacity(0.6) : Color.white.opacity(0.06), lineWidth: 1)
                    )
                }
                
                // 128k Option
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    chatVM.configuredMaxContext = 131072
                    UserDefaults.standard.set(131072, forKey: "strata_active_context_limit")
                    chatVM.setPreferredVariant("swift-128k", for: chatVM.backend)
                    Task { await statusVM.switchVariant("swift-128k") }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("128k Balanced")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                Text("~75 tok/s")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(hex: "ffd60a"))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color(hex: "ffd60a").opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            Text("4-bit KV · 8.3 GB GPU VRAM · Zero disk reads")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        if active == "swift-128k" {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(hex: "7c5cff"))
                                .font(.system(size: 16))
                        }
                    }
                    .padding(12)
                    .background(active == "swift-128k" ? Color(hex: "7c5cff").opacity(0.18) : Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(active == "swift-128k" ? Color(hex: "7c5cff").opacity(0.6) : Color.white.opacity(0.06), lineWidth: 1)
                    )
                }
                
                // 160k Option
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    chatVM.configuredMaxContext = 163840
                    UserDefaults.standard.set(163840, forKey: "strata_active_context_limit")
                    chatVM.setPreferredVariant("swift-160k", for: chatVM.backend)
                    Task { await statusVM.switchVariant("swift-160k") }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("160k Maximum Speed")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                Text("~65–75 tok/s")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(hex: "34c759"))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color(hex: "34c759").opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            Text("k8v4 KV · 7.3 GB GPU VRAM · Zero disk reads · Fully resident")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        if active == "swift-160k" {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(hex: "7c5cff"))
                                .font(.system(size: 16))
                        }
                    }
                    .padding(12)
                    .background(active == "swift-160k" ? Color(hex: "7c5cff").opacity(0.18) : Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(active == "swift-160k" ? Color(hex: "7c5cff").opacity(0.6) : Color.white.opacity(0.06), lineWidth: 1)
                    )
                }
                
                // 262k Option
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    chatVM.configuredMaxContext = 262144
                    UserDefaults.standard.set(262144, forKey: "strata_active_context_limit")
                    chatVM.setPreferredVariant("swift", for: chatVM.backend)
                    Task { await statusVM.switchVariant("swift") }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("262k Maximum")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                Text("~56 tok/s")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color.white.opacity(0.5))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Capsule())
                            }
                            Text("k8v4 KV · 6.3 GB GPU VRAM · Maximum context size")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        if active == "swift" || active == "original" {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(hex: "7c5cff"))
                                .font(.system(size: 16))
                        }
                    }
                    .padding(12)
                    .background((active == "swift" || active == "original") ? Color(hex: "7c5cff").opacity(0.18) : Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke((active == "swift" || active == "original") ? Color(hex: "7c5cff").opacity(0.6) : Color.white.opacity(0.06), lineWidth: 1)
                    )
                }
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // GPU Stats
            HStack {
                Text("RTX 5070 Ti")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(gpuString)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(14)
        .background(Color(hex: "181826"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    @ViewBuilder
    private var modelActionsSection: some View {
        VStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await statusVM.wake() }
            } label: {
                HStack {
                    Image(systemName: "bolt.fill")
                    Text("Wake Model (Pre-warm)")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await statusVM.unload() }
            } label: {
                HStack {
                    Image(systemName: "moon.fill")
                    Text("Free VRAM (Unload Model)")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "ff6961"))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color(hex: "ff453a").opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    @ViewBuilder
    private var pcPowerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PC POWER & WAKE-ON-LAN")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(statusVM.isOnline ? "PC Online" : "PC Asleep / Offline")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(statusVM.isOnline ? Color.green : Color.orange)
            }
            
            if let feedback = statusVM.powerFeedback {
                Text(feedback)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "ffd60a"))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: "ffd60a").opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { await statusVM.setStealthMode(enabled: true) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "moon.fill")
                        .foregroundColor(Color(hex: "ffd60a"))
                    Text("🌙 Low Power Stealth Mode")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text("0 RGB • Screen Off")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            
            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    statusVM.wakePC()
                } label: {
                    HStack {
                        Image(systemName: "bolt.horizontal.fill")
                        Text("Wake PC")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color(hex: "7c5cff"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showSleepAlert = true
                } label: {
                    HStack {
                        Image(systemName: "moon.zzz.fill")
                        Text("Sleep PC")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "b8a5ff"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color(hex: "7c5cff").opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "7c5cff").opacity(0.3), lineWidth: 1))
                }
                
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showShutdownAlert = true
                } label: {
                    HStack {
                        Image(systemName: "power")
                        Text("Shut Down")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "ff6961"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color(hex: "ff453a").opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "ff453a").opacity(0.3), lineWidth: 1))
                }
            }
            
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
                Text("End-to-End Encrypted (Zero-Knowledge AES-256-GCM)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(Color(hex: "181826"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
