import SwiftUI
import UniformTypeIdentifiers

public struct LocalModelManagerView: View {
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            LocalModelManagerContentView(isModalSheet: true)
        }
        .preferredColorScheme(.dark)
    }
}

public struct LocalModelManagerContentView: View {
    @ObservedObject var engine = LocalInferenceEngine.shared
    @Environment(\.dismiss) private var dismiss
    public var isModalSheet: Bool
    
    @State private var showFileImporter: Bool = false
    @State private var importError: String? = nil
    
    public init(isModalSheet: Bool = false) {
        self.isModalSheet = isModalSheet
    }
    
    public var body: some View {
        ZStack {
            Color(hex: "09090f").ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 18) {
                    hardwareTelemetryCard
                    activeModelSelectorCard
                    incompleteDownloadsCard
                    modelPreloadUnloadCard
                    uncensoredLoRACard
                    advancedEngineOptionsCard
                    parameterTuningCard
                    filesAppCard
                    cloudDownloadCard
                    wifiSyncCard
                    
                    Spacer(minLength: 28)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
        .navigationTitle("On-Device Engine (MiniCPM)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isModalSheet {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "00f2fe"))
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let selected = urls.first {
                    Task {
                        do {
                            try await engine.importModel(from: selected)
                        } catch {
                            self.importError = error.localizedDescription
                        }
                    }
                }
            case .failure(let err):
                self.importError = err.localizedDescription
            }
        }
        .alert("Import Error", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Unknown error importing model.")
        }
        .onAppear {
            engine.scanModels()
        }
    }
    
    // MARK: - Subview: Hardware & RAM Telemetry
    @ViewBuilder
    private var hardwareTelemetryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cpu.fill")
                    .foregroundColor(Color(hex: "00f2fe"))
                Text("IPHONE 17 PRO HARDWARE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("Apple A19 Pro")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "00f2fe"))
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(engine.availableMemoryFormatted)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Available Unified RAM")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Divider().frame(height: 36).background(Color.white.opacity(0.15))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(engine.residentMemoryFormatted)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "34d399"))
                    Text("App Footprint")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Entitlement status badge
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(Color(hex: "34d399"))
                    .font(.system(size: 12))
                Text("6.5 GB Metal GPU Ceiling · 9.5 GB Process Limit (12 GB iPhone)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(hex: "34d399").opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .background(Color(hex: "141420"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Subview: Active Model Selector Card
    @ViewBuilder
    private var activeModelSelectorCard: some View {
        let downloadedModels = engine.availableModels.filter { $0.isDownloaded && !$0.isIncomplete }
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.badge.questionmark.fill")
                    .foregroundColor(Color(hex: "00f2fe"))
                Text("ACTIVE ON-DEVICE MODEL")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                if let active = engine.activeModel {
                    Text(active.isDownloaded ? "● READY" : "○ NOT DOWNLOADED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(active.isDownloaded ? Color(hex: "34d399") : Color(hex: "ffd60a"))
                }
            }
            
            if downloadedModels.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(Color(hex: "ffd60a"))
                    Text("No complete models downloaded yet. Download MiniCPM-V 4.7 IQ3 below to enable on-device inference.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(10)
                .background(Color(hex: "ffd60a").opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Text("Tap any downloaded model below to switch the active engine for on-device inference.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.65))
                
                VStack(spacing: 10) {
                    ForEach(downloadedModels) { model in
                        let isActive = (engine.activeModel?.filename == model.filename)
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                engine.selectActiveModel(model)
                            }
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(isActive ? Color(hex: "00f2fe") : .white.opacity(0.3))
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(model.name)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundColor(.white)
                                        
                                        if isActive {
                                            Text("ACTIVE")
                                                .font(.system(size: 9, weight: .black))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color(hex: "00f2fe").opacity(0.2))
                                                .foregroundColor(Color(hex: "00f2fe"))
                                                .clipShape(Capsule())
                                        }
                                        
                                        if isActive && engine.isModelLoadedInMemory {
                                            Text(engine.isOfflineFallbackActive ? "ACTIVE (OFFLINE)" : "IN VRAM")
                                                .font(.system(size: 9, weight: .black))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color(hex: "34d399").opacity(0.2))
                                                .foregroundColor(Color(hex: "34d399"))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    
                                    HStack(spacing: 6) {
                                        Text(model.sizeFormatted)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(Color(hex: "34d399"))
                                        Text("•")
                                            .foregroundColor(.white.opacity(0.3))
                                        Text(model.activeParams)
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.6))
                                        Text("•")
                                            .foregroundColor(.white.opacity(0.3))
                                        Text(model.ramFootprint)
                                            .font(.system(size: 11))
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                                
                                Spacer()
                                
                                if !isActive {
                                    Text("Switch")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color(hex: "00f2fe"))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color(hex: "00f2fe").opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isActive ? Color(hex: "00f2fe").opacity(0.08) : Color.white.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isActive ? Color(hex: "00f2fe").opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(14)
        .background(Color(hex: "141420"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Subview: Incomplete Downloads Card
    @ViewBuilder
    private var incompleteDownloadsCard: some View {
        let incompleteModels = engine.availableModels.filter { $0.isIncomplete }
        if !incompleteModels.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color(hex: "ff453a"))
                    Text("INCOMPLETE DOWNLOAD DETECTED")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "ff453a"))
                    Spacer()
                    Text("Action Required")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "ff453a"))
                }
                
                Text("A download was interrupted or truncated before completion. Truncated files cannot be loaded by llama.cpp.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.75))
                
                ForEach(incompleteModels) { model in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Saved: \(model.sizeFormatted) of \(model.expectedSizeFormatted) (Truncated)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(Color(hex: "ffd60a"))
                            }
                            Spacer()
                        }
                        
                        HStack(spacing: 10) {
                            if let _ = model.downloadUrl {
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    engine.deleteModel(filename: model.filename)
                                    engine.startDownload(model: model)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("Re-download")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(hex: "00f2fe"))
                                    .clipShape(Capsule())
                                }
                            }
                            
                            Button(role: .destructive) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                engine.deleteModel(filename: model.filename)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                    Text("Delete File (\(model.sizeFormatted))")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(Color(hex: "ff453a"))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(hex: "ff453a").opacity(0.12))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(hex: "ff453a").opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "ff453a").opacity(0.25), lineWidth: 1))
                }
            }
            .padding(14)
            .background(Color(hex: "18121a"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "ff453a").opacity(0.3), lineWidth: 1))
        }
    }
    
    // MARK: - Subview: Model VRAM State & Action Card (Load / Unload)
    @ViewBuilder
    private var modelPreloadUnloadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "memorychip.fill")
                    .foregroundColor(Color(hex: "00f2fe"))
                Text("MODEL VRAM RESIDENCE MATRIX")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(engine.isLoadingModel ? "● LOADING..." : (engine.isModelLoadedInMemory ? (engine.hasPendingEngineReload ? "● RELOAD PENDING" : "● LOADED") : "○ STANDBY"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(engine.isLoadingModel || engine.hasPendingEngineReload ? Color(hex: "ffd60a") : (engine.isModelLoadedInMemory ? Color(hex: "34d399") : .white.opacity(0.4)))
            }
            
            Text(engine.isLoadingModel
                 ? "Safely releasing previous Metal buffers and allocating unified VRAM..."
                 : (engine.isModelLoadedInMemory
                    ? (engine.hasPendingEngineReload
                       ? "You changed engine parameters. Tap 'Apply Changes' below (or send a chat message) to reload safely without overlapping VRAM buffers."
                       : "Model weights are active in Metal unified VRAM for instant responses.")
                    : "Model is in standby with 0 MB resident VRAM. Weights will load on first prompt or when preloaded."))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 10) {
                if engine.isLoadingModel {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Color(hex: "00f2fe"))
                        Text("Loading 35B-A3B Engine...")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "00f2fe"))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color(hex: "00f2fe").opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if engine.isModelLoadedInMemory {
                    if engine.hasPendingEngineReload {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            engine.preloadActiveModel()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                    .font(.system(size: 12))
                                Text("Apply & Reload")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(Color(hex: "ffd60a"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        engine.unloadActiveModel()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "eject.fill")
                                .font(.system(size: 12))
                            Text(engine.hasPendingEngineReload ? "Unload" : "Unload from Memory (0 MB)")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "ff453a"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Color(hex: "ff453a").opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "ff453a").opacity(0.3), lineWidth: 1))
                    }
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        engine.preloadActiveModel()
                    } label: {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 12))
                            Text("Preheat to Unified VRAM")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Color(hex: "00f2fe"))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(14)
        .background(Color(hex: "141420"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Subview: Uncensored Abliterated LoRA Card
    @ViewBuilder
    private var uncensoredLoRACard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lock.open.trianglebadge.exclamationmark.fill")
                    .foregroundColor(Color(hex: "ffd60a"))
                Text("UNCENSORED ABLITERATION (LORA)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(engine.bundledLESLoRAURL != nil ? "BUILT-IN · 1.4 MB" : "READY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: "ffd60a").opacity(0.18))
                    .foregroundColor(Color(hex: "ffd60a"))
                    .clipShape(Capsule())
            }
            
            Text("Directional residual-stream ablation tailored for 35B-A3B LES Mobile removes refusal boundaries at inference time with zero loss in reasoning intelligence and instant hot-swap.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            
            Toggle(isOn: $engine.isUncensoredLoRAEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uncensored LoRA Adapter")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(engine.isUncensoredLoRAEnabled ? "Active (Zero Refusals · Hot-Swapped in VRAM)" : "Disabled (Standard Model Behavior)")
                        .font(.system(size: 11))
                        .foregroundColor(engine.isUncensoredLoRAEnabled ? Color(hex: "ffd60a") : .white.opacity(0.5))
                }
            }
            .tint(Color(hex: "ffd60a"))
        }
        .padding(14)
        .background(Color(hex: "141420"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Subview: Real MoE-SSD Metal VRAM Turbo, DSpark & Vision Tower Card
    @ViewBuilder
    private var advancedEngineOptionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "bolt.badge.automatic.fill")
                    .foregroundColor(Color(hex: "00f2fe"))
                Text("METAL VRAM TURBO & EXPERT CACHE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(engine.estimatedVRAMCacheString(for: engine.moeCacheWindowC))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(hex: "34d399").opacity(0.16))
                    .foregroundColor(Color(hex: "34d399"))
                    .clipShape(Capsule())
            }
            
            if engine.isModelLoadedInMemory && engine.hasPendingEngineReload {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    engine.preloadActiveModel()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        Text("Apply Engine Settings & Safely Reload VRAM")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color(hex: "ffd60a"))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            
            // 1. VRAM Expert Cache Window (c)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Resident Expert Cache Window")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    if let hitRate = engine.lastMoECacheHitRate {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                            Text(String(format: "%.1f%% Cache Hit", hitRate))
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(hex: "34d399").opacity(0.18))
                        .foregroundColor(Color(hex: "34d399"))
                        .clipShape(Capsule())
                    }
                    Text(engine.moeCacheWindowC == 0 ? "AUTO (c=\(engine.lastResolvedWindowC))" : "c = \(engine.moeCacheWindowC)/256")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "00f2fe"))
                }
                
                let windowOptions: [(label: String, val: Int)] = [
                    ("Auto (64)", 0),
                    ("48 (4.8G)", 48),
                    ("64 (5.8G)", 64),
                    ("72 (6.3G)", 72),
                    ("80 (6.8G)", 80),
                    ("96 (7.8G)", 96),
                    ("112 (8.8G)", 112),
                    ("128 (Max)", 128)
                ]
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(windowOptions, id: \.val) { item in
                        let selected = (engine.moeCacheWindowC == item.val)
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            engine.moeCacheWindowC = item.val
                        } label: {
                            Text(item.label)
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(selected ? Color(hex: "00f2fe") : Color.white.opacity(0.06))
                                .foregroundColor(selected ? .black : .white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                
                Text("Controls how many routed experts per layer stay wired in Metal unified VRAM. On iPhone 17 Pro with 12 GB RAM, you have up to ~9.5 GB usable headroom. Auto (c=64, ~5.8 GB) provides smooth balanced performance; higher values (c=72 to 128) maximize cache hits and tokens/sec.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.top, 2)
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // 2. Cluster Table Prewarm Level
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Cluster Expert Prewarm")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(engine.moePrewarmLevel == 0 ? "OFF" : "Top \(engine.moePrewarmLevel) Experts/Layer")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "00f2fe"))
                }
                
                HStack(spacing: 8) {
                    ForEach([0, 8, 16, 32, 48], id: \.self) { lvl in
                        let selected = (engine.moePrewarmLevel == lvl)
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            engine.moePrewarmLevel = lvl
                        } label: {
                            Text(lvl == 0 ? "Off" : (lvl == 16 ? "16 (Fast)" : "\(lvl)"))
                                .font(.system(size: 12, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(selected ? Color(hex: "00f2fe") : Color.white.opacity(0.06))
                                .foregroundColor(selected ? .black : .white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                
                Text("Pre-fills the decode window with the highest-frequency K4 cluster experts automatically when model loads. Level 16 gives an immediate smooth first token without stalling.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // 3. DSpark Speculative Decoding Accelerator (dspark-MiniCPM-V-4_7-35B-A3B-Q8_0.gguf)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(Color(hex: "ffd60a"))
                        .font(.system(size: 12))
                    Text("DSpark Speculative Accelerator (MTP)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    if let accRate = engine.lastDSparkAcceptanceRate, let tpsBonus = engine.lastDSparkTokensPerStep {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10))
                            Text(String(format: "%.0f%% Accept · +%.2f tok/step", accRate, tpsBonus))
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(hex: "ffd60a").opacity(0.18))
                        .foregroundColor(Color(hex: "ffd60a"))
                        .clipShape(Capsule())
                    }
                    Text(engine.isDSparkDownloaded ? (engine.isDSparkEnabled ? "ACTIVE · N=\(engine.dsparkDraftNMax)" : "INSTALLED") : "405 MB")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(engine.isDSparkDownloaded ? Color(hex: "34d399") : Color(hex: "ffd60a"))
                }
                
                if engine.isDSparkDownloaded {
                    Toggle(isOn: $engine.isDSparkEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable DSpark Multi-Token Drafting")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            Text("0.39B 5-layer speculative head drafts \(engine.dsparkDraftNMax) tokens per step from target layers [3,11,19,27,35]")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .tint(Color(hex: "ffd60a"))
                    
                    if engine.isDSparkEnabled {
                        HStack(spacing: 8) {
                            Text("Draft Width:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                            ForEach([1, 2, 3, 4], id: \.self) { n in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    engine.dsparkDraftNMax = n
                                } label: {
                                    Text(n == 2 ? "n=2 (Best)" : "n=\(n)")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(engine.dsparkDraftNMax == n ? Color(hex: "ffd60a") : Color.white.opacity(0.06))
                                        .foregroundColor(engine.dsparkDraftNMax == n ? .black : .white)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                engine.deleteDSparkDraft()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "ff453a"))
                                    .padding(6)
                            }
                        }
                    }
                } else if engine.isDownloading && engine.downloadTargetFilename == "dspark-MiniCPM-V-4_7-35B-A3B-Q8_0.gguf" {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Downloading DSpark Draft Head...")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Text(engine.downloadSpeed)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(hex: "ffd60a"))
                        }
                        ProgressView(value: engine.downloadProgress)
                            .tint(Color(hex: "ffd60a"))
                    }
                } else {
                    Text("OpenBMB's official 0.39B DSpark draft head reads intermediate hidden states and drafts multiple tokens in parallel for lossless speculative acceleration.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        engine.startDownloadDSparkDraft()
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13))
                            Text("Download DSpark Speculative Draft (405 MB)")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color(hex: "ffd60a"))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // 5. Multimodal Vision Projector (mmproj-v47.gguf)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "eye.fill")
                        .foregroundColor(Color(hex: "00f2fe"))
                        .font(.system(size: 12))
                    Text("Multimodal Vision Projector (SigLIP)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(engine.isVisionProjectorDownloaded ? "INSTALLED" : "1.12 GB")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(engine.isVisionProjectorDownloaded ? Color(hex: "34d399") : Color(hex: "ffd60a"))
                }
                
                if engine.isVisionProjectorDownloaded {
                    HStack {
                        Text("Vision encoder ready — attach any photo in chat for on-device visual analysis.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.65))
                        Spacer()
                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            engine.deleteVisionProjector()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "ff453a"))
                                .padding(6)
                        }
                    }
                } else if engine.isDownloading && engine.downloadTargetFilename == "mmproj-v47.gguf" {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Downloading Vision Tower...")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Text(engine.downloadSpeed)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color(hex: "00f2fe"))
                        }
                        ProgressView(value: engine.downloadProgress)
                            .tint(Color(hex: "00f2fe"))
                    }
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        engine.startDownloadVisionProjector()
                    } label: {
                        HStack {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 13))
                            Text("Download Vision Tower (1.12 GB)")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color(hex: "00f2fe"))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(14)
        .background(Color(hex: "141420"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Subview: MiniCPM-V 4.7 Context, 4-Bit KV Quant & Parameter Tuning
    @ViewBuilder
    private var parameterTuningCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(Color(hex: "00f2fe"))
                Text("CONTEXT WINDOW & KV QUANTIZATION")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text(String(format: "%.1f KiB / tok KV", engine.kvKiBPerToken))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "34d399"))
            }
            
            // Context Window (2K, 4K, 8K, 16K)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Context Window")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    let kvMB = Int((Double(engine.contextLength) * engine.kvKiBPerToken / 1024.0).rounded())
                    Text("\(engine.contextLength.formatted()) tok (~\(kvMB) MB RAM)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "00f2fe"))
                }
                
                HStack(spacing: 8) {
                    ForEach([2048, 4096, 8192, 16384], id: \.self) { ctx in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            engine.contextLength = ctx
                        } label: {
                            Text("\(ctx / 1024)K")
                                .font(.system(size: 12, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(engine.contextLength == ctx ? Color(hex: "00f2fe") : Color.white.opacity(0.06))
                                .foregroundColor(engine.contextLength == ctx ? .black : .white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                
                Text("30 of 40 layers use constant-memory Gated Delta Net (SSM) state; only 10 attention layers use KV cache.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            // KV Cache Quantization (4-bit Q4_0 default, 8-bit Q8_0, 16-bit FP16)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("KV Cache Quantization")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text(engine.kvQuantTypeInt == 2 ? "4-Bit (Q4_0 · 3.5x Smaller)" : (engine.kvQuantTypeInt == 1 ? "8-Bit (Q8_0)" : "16-Bit (FP16)"))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "34d399"))
                }
                
                HStack(spacing: 8) {
                    let kvOpts: [(label: String, key: String)] = [
                        ("4-Bit (Q4_0)", "q4_0"),
                        ("8-Bit (Q8_0)", "q8_0"),
                        ("16-Bit (FP16)", "f16")
                    ]
                    ForEach(kvOpts, id: \.key) { opt in
                        let selected = (engine.kvCacheQuant.lowercased() == opt.key)
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            engine.kvCacheQuant = opt.key
                        } label: {
                            Text(opt.label)
                                .font(.system(size: 11, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(selected ? Color(hex: "34d399") : Color.white.opacity(0.06))
                                .foregroundColor(selected ? .black : .white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                
                Text("Running KV cache at **4-Bit (`Q4_0`)** shrinks 8K context to just **~45 MB** (down from 160 MB at FP16) and reduces Metal memory bandwidth during attention decoding.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            // Temperature
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Sampling Temperature")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%.2f", engine.temperature))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "00f2fe"))
                }
                Slider(value: $engine.temperature, in: 0.1...1.2, step: 0.05)
                    .tint(Color(hex: "00f2fe"))
            }
            
            // Lookahead Prefetch Depth & CPU Threads
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("LES Prefetch (Sweet Spot: 4)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("d = \(engine.moeLookaheadDepth)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "00f2fe"))
                    }
                    Slider(value: Binding(
                        get: { Double(engine.moeLookaheadDepth) },
                        set: { engine.moeLookaheadDepth = Int($0) }
                    ), in: 2...12, step: 2)
                        .tint(Color(hex: "00f2fe"))
                }
                .frame(maxWidth: .infinity)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("CPU Threads")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(engine.threadCount) cores")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "00f2fe"))
                    }
                    Slider(value: Binding(
                        get: { Double(engine.threadCount) },
                        set: { engine.threadCount = Int($0) }
                    ), in: 2...6, step: 1)
                    .tint(Color(hex: "00f2fe"))
                }
                .frame(maxWidth: .infinity)
            }
            
            // Lookahead Expert Scheduling toggle
            Toggle(isOn: $engine.lookaheadScheduling) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lookahead Expert Prefetching (LES)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Predicts next-layer top-d experts while GPU computes layer L (`d=4` is optimal with large VRAM cache)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .tint(Color(hex: "00f2fe"))
        }
        .padding(14)
        .background(Color(hex: "141420"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Subview: Apple Files App & Explorer
    @ViewBuilder
    private var filesAppCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(Color(hex: "ffd60a"))
                Text("FILES APP / LOCAL STORAGE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Button {
                    engine.scanModels()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "00f2fe"))
                }
            }
            
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundColor(Color(hex: "ffd60a"))
                    .font(.system(size: 14))
                Text("Drop any `.gguf` file into **Files → On My iPhone → Strata Chat** via AirDrop, Safari or USB.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(10)
            .background(Color(hex: "ffd60a").opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            Button {
                showFileImporter = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .bold))
                    Text("Import .gguf from Files…")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color(hex: "00f2fe"))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // Detected local models
            let downloaded = engine.availableModels.filter { $0.isDownloaded && !$0.isIncomplete }
            if downloaded.isEmpty {
                Text("No complete .gguf models currently found in app storage.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.top, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(downloaded) { model in
                        let isActive = (engine.activeModel?.filename == model.filename)
                        HStack {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation {
                                    engine.selectActiveModel(model)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(isActive ? Color(hex: "00f2fe") : .white.opacity(0.3))
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(model.name)
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.white)
                                            if isActive {
                                                Text("ACTIVE")
                                                    .font(.system(size: 9, weight: .black))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(Color(hex: "00f2fe").opacity(0.2))
                                                    .foregroundColor(Color(hex: "00f2fe"))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        HStack(spacing: 6) {
                                            Text(model.sizeFormatted)
                                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                .foregroundColor(Color(hex: "34d399"))
                                            Text("•")
                                                .foregroundColor(.white.opacity(0.3))
                                            Text(model.activeParams)
                                                .font(.system(size: 11))
                                                .foregroundColor(.white.opacity(0.6))
                                        }
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Spacer()
                            
                            Button(role: .destructive) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                engine.deleteModel(filename: model.filename)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(hex: "ff453a"))
                                    .padding(8)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(10)
                        .background(isActive ? Color(hex: "00f2fe").opacity(0.06) : Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isActive ? Color(hex: "00f2fe").opacity(0.3) : Color.clear, lineWidth: 1))
                    }
                }
            }
        }
        .padding(14)
        .background(Color(hex: "141420"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Subview: Direct Cloud Downloader
    @ViewBuilder
    private var cloudDownloadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "icloud.and.arrow.down.fill")
                    .foregroundColor(Color(hex: "7c5cff"))
                Text("DIRECT CLOUD DOWNLOAD")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("Hugging Face / ModelScope")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            if engine.isDownloading && engine.downloadTargetFilename != "MiniCPM-V-4.7-35B-A3B-Uncensored-LoRA.gguf" {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(engine.downloadTargetModel ?? "Downloading Model...")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Text(engine.downloadSpeed)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color(hex: "00f2fe"))
                    }
                    
                    ProgressView(value: engine.downloadProgress)
                        .tint(Color(hex: "00f2fe"))
                    
                    HStack {
                        Text("\(Int(engine.downloadProgress * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Button("Cancel") {
                            engine.cancelDownload()
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "ff453a"))
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                let recModels = engine.availableModels.filter { !$0.isDownloaded && $0.downloadUrl != nil }
                ForEach(recModels) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            Text("\(model.activeParams) • \(model.ramFootprint)")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        Spacer()
                        
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            engine.startDownload(model: model)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Get")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color(hex: "7c5cff"))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(14)
        .background(Color(hex: "141420"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Subview: Local Wi-Fi Sync from PC
    @ViewBuilder
    private var wifiSyncCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "wifi")
                    .foregroundColor(Color(hex: "34d399"))
                Text("LOCAL WI-FI PC SYNC")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Text("Transfer GGUF weights directly from your PC host (`192.168.1.39:8765`) over local Wi-Fi at 50–100 MB/s without consuming internet bandwidth.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(hex: "141420"))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
