import Foundation
import Combine
import SwiftUI
import Darwin
import Metal

public struct LocalModelFile: Identifiable, Hashable, Codable {
    public var id: String { filename }
    public let name: String
    public let filename: String
    public let sizeBytes: Int64
    public let isDownloaded: Bool
    public let downloadUrl: String?
    public let architecture: String
    public let activeParams: String
    public let ramFootprint: String
    public let isMoE: Bool
    public var isIncomplete: Bool
    public var expectedSizeBytes: Int64
    
    public init(
        name: String,
        filename: String,
        sizeBytes: Int64,
        isDownloaded: Bool,
        downloadUrl: String?,
        architecture: String,
        activeParams: String,
        ramFootprint: String,
        isMoE: Bool,
        isIncomplete: Bool = false,
        expectedSizeBytes: Int64 = 0
    ) {
        self.name = name
        self.filename = filename
        self.sizeBytes = sizeBytes
        self.isDownloaded = isDownloaded
        self.downloadUrl = downloadUrl
        self.architecture = architecture
        self.activeParams = activeParams
        self.ramFootprint = ramFootprint
        self.isMoE = isMoE
        self.isIncomplete = isIncomplete
        self.expectedSizeBytes = expectedSizeBytes > 0 ? expectedSizeBytes : sizeBytes
    }
    
    public var sizeFormatted: String {
        let gb = Double(sizeBytes) / (1024.0 * 1024.0 * 1024.0)
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(sizeBytes) / (1024.0 * 1024.0)
        return String(format: "%.0f MB", mb)
    }
    
    public var expectedSizeFormatted: String {
        guard expectedSizeBytes > 0 else { return "" }
        let gb = Double(expectedSizeBytes) / (1024.0 * 1024.0 * 1024.0)
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(expectedSizeBytes) / (1024.0 * 1024.0)
        return String(format: "%.0f MB", mb)
    }
}

public class LocalInferenceEngine: NSObject, ObservableObject, URLSessionDownloadDelegate {
    public static let shared = LocalInferenceEngine()
    
    // MARK: - Published State
    @Published public var availableModels: [LocalModelFile] = []
    @Published public var activeModel: LocalModelFile? = nil
    
    // Memory telemetry (Mach phys_footprint + Metal GPU allocated buffers)
    @Published public var availableMemoryBytes: UInt64 = 0
    @Published public var residentMemoryBytes: UInt64 = 0
    @Published public var metalAllocatedBytes: UInt64 = 0
    
    // Live KV Context Telemetry from C++ Engine
    @Published public var activeContextUsedTokens: Int = 0
    @Published public var activeContextMaxTokens: Int = 8192
    @Published public var activeContextCachedTokens: Int = 0
    
    // Live MoE Cache & DSpark Telemetry from C++ Engine
    @Published public var lastMoECacheHitRate: Double? = nil
    @Published public var lastDSparkAcceptanceRate: Double? = nil
    @Published public var lastDSparkTokensPerStep: Double? = nil
    @Published public var lastResolvedWindowC: Int = 64
    
    // Inference Parameters (OpenBMB Recommended Defaults)
    @Published public var temperature: Double {
        didSet { UserDefaults.standard.set(temperature, forKey: "local_llm_temp") }
    }
    @Published public var topP: Double {
        didSet { UserDefaults.standard.set(topP, forKey: "local_llm_top_p") }
    }
    @Published public var topK: Int {
        didSet { UserDefaults.standard.set(topK, forKey: "local_llm_top_k") }
    }
    @Published public var repetitionPenalty: Double {
        didSet { UserDefaults.standard.set(repetitionPenalty, forKey: "local_llm_rep_penalty") }
    }
    @Published public var contextLength: Int {
        didSet {
            UserDefaults.standard.set(contextLength, forKey: "local_llm_n_ctx")
            activeContextMaxTokens = contextLength
            if isModelLoadedInMemory {
                hasPendingEngineReload = true
            }
        }
    }
    @Published public var threadCount: Int {
        didSet { UserDefaults.standard.set(threadCount, forKey: "local_llm_n_threads") }
    }
    @Published public var lookaheadScheduling: Bool {
        didSet {
            UserDefaults.standard.set(lookaheadScheduling, forKey: "local_llm_les_enabled")
            let depth = lookaheadScheduling ? moeLookaheadDepth : 0
            Task { await OpenBMBLlamaEngine.shared.setLookaheadDepth(depth) }
        }
    }
    
    // Real MoE-SSD Metal VRAM Cache & Prefetch Controls
    /// `0` = Auto Optimal (~7.5 GB total VRAM with c=72 on 9.5 GB headroom), or explicit `48 / 64 / 72 / 80 / 96 / 112 / 128`
    @Published public var moeCacheWindowC: Int {
        didSet {
            UserDefaults.standard.set(moeCacheWindowC, forKey: "local_llm_moe_window_c")
            OpenBMBLlamaEngine.resetWindowCrashCap()
            if isModelLoadedInMemory {
                hasPendingEngineReload = true
            }
        }
    }
    /// Lookahead prefetch depth `d` (`0...16`, default `4` — OpenBMB's measured sweet spot when VRAM cache window is active)
    @Published public var moeLookaheadDepth: Int {
        didSet {
            UserDefaults.standard.set(moeLookaheadDepth, forKey: "local_llm_moe_lookahead_d")
            let depth = lookaheadScheduling ? moeLookaheadDepth : 0
            Task { await OpenBMBLlamaEngine.shared.setLookaheadDepth(depth) }
        }
    }
    /// Cluster table prewarm level (`0 / 16 / 32 / 48`, default `16` for rapid token generation)
    @Published public var moePrewarmLevel: Int {
        didSet {
            UserDefaults.standard.set(moePrewarmLevel, forKey: "local_llm_moe_prewarm")
            if isModelLoadedInMemory {
                hasPendingEngineReload = true
            }
        }
    }
    /// Active MoE experts per token during decode (Locked to 8 = p8d8 for graph dimension stability)
    @Published public var moeKDecode: Int {
        didSet {
            UserDefaults.standard.set(8, forKey: "local_llm_moe_k_decode")
            if isModelLoadedInMemory {
                hasPendingEngineReload = true
            }
        }
    }
    /// DSpark Speculative Decoding (`true` when draft model is installed & enabled)
    @Published public var isDSparkEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isDSparkEnabled, forKey: "local_llm_dspark_enabled")
            if isModelLoadedInMemory {
                hasPendingEngineReload = true
            }
        }
    }
    /// DSpark draft block width (`1 / 2 / 3 / 4`, default `2`)
    @Published public var dsparkDraftNMax: Int {
        didSet {
            UserDefaults.standard.set(dsparkDraftNMax, forKey: "local_llm_dspark_n_max")
            if isModelLoadedInMemory && isDSparkEnabled {
                hasPendingEngineReload = true
            }
        }
    }
    
    // Legacy compatibility + active KV Cache Quantization (`q4_0` default, `q8_0`, `f16`)
    @Published public var flashAttention: Bool {
        didSet { UserDefaults.standard.set(flashAttention, forKey: "local_llm_flash_attn") }
    }
    @Published public var mtpSpeculative: Bool {
        didSet { UserDefaults.standard.set(mtpSpeculative, forKey: "local_llm_mtp_speculative") }
    }
    @Published public var kvCacheQuant: String {
        didSet {
            UserDefaults.standard.set(kvCacheQuant, forKey: "local_llm_kv_quant")
            if isModelLoadedInMemory {
                hasPendingEngineReload = true
            }
        }
    }
    
    public var kvQuantTypeInt: Int {
        switch kvCacheQuant.lowercased() {
        case "q4_0", "4bit": return 2
        case "q8_0", "8bit": return 1
        default: return 0
        }
    }
    
    public var kvKiBPerToken: Double {
        switch kvQuantTypeInt {
        case 2: return 5.7
        case 1: return 10.6
        default: return 20.0
        }
    }
    
    @Published public var isUncensoredLoRAEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isUncensoredLoRAEnabled, forKey: "local_llm_uncensored_lora")
            if isModelLoadedInMemory {
                let path: String? = (isUncensoredLoRAEnabled && isLoRADownloaded) ? loraFileURL.path : nil
                Task { await OpenBMBLlamaEngine.shared.hotSwapLoRA(path) }
            }
        }
    }
    @Published public var isLoRADownloaded: Bool = true
    @Published public var isVisionProjectorDownloaded: Bool = false
    @Published public var isDSparkDownloaded: Bool = false
    @Published public var isModelLoadedInMemory: Bool = false
    @Published public var isLoadingModel: Bool = false
    @Published public var hasPendingEngineReload: Bool = false
    @Published public var isOfflineFallbackActive: Bool = false
    
    public var jetsamLimitBytes: UInt64 {
        // On 12 GB iPhones (iPhone 17 Pro), os_proc_available_memory() + residentMemoryBytes
        // reaches up to ~9.5 GB. Allow full utilization up to process ceiling.
        let dynamicCeiling = availableMemoryBytes + residentMemoryBytes
        return max(9_663_676_416, dynamicCeiling) // ~9.5 GB ceiling
    }
    
    /// Built-in 1.4 MB Uncensored Abliteration LoRA tailored for 35B-A3B LES Mobile (bundled in app resources)
    public var bundledLESLoRAURL: URL? {
        Bundle.main.url(forResource: "MiniCPM-V-4.7-35B-A3B-LES-Uncensored-LoRA", withExtension: "gguf")
    }
    
    public var loraFileURL: URL {
        if let bundled = bundledLESLoRAURL, FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        return documentsDirectory.appendingPathComponent("MiniCPM-V-4.7-35B-A3B-Uncensored-LoRA.gguf")
    }
    
    public var visionProjectorFileURL: URL {
        documentsDirectory.appendingPathComponent("mmproj-v47.gguf")
    }
    
    public var visionProjector1BFileURL: URL {
        documentsDirectory.appendingPathComponent("mmproj-v47-1b.gguf")
    }
    
    public var dsparkDraftFileURL: URL {
        documentsDirectory.appendingPathComponent("dspark-MiniCPM-V-4_7-35B-A3B-Q8_0.gguf")
    }
    
    /// Estimated total Metal VRAM footprint in GB for a given `c` window on 35B-A3B LES
    public func estimatedVRAMCacheString(for windowC: Int) -> String {
        let autoC = 64
        let effectiveC = windowC == 0 ? autoC : windowC
        let totalSlots = effectiveC + (lookaheadScheduling ? moeLookaheadDepth : 0)
        let dsparkGiB = (isDSparkEnabled && isDSparkDownloaded) ? 0.45 : 0.0
        // Base (1.35 GiB backbone + 0.45 GiB slot_bank/compute + 0.25 GiB Metal/KV = 2.05 GiB) + 61.4 MiB/slot
        let totalGiB = 2.05 + dsparkGiB + (Double(totalSlots) * 61.4 / 1024.0)
        return String(format: "~%.1f GB VRAM", totalGiB)
    }
    
    // Downloader state
    @Published public var isDownloading: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var downloadSpeed: String = ""
    @Published public var downloadTargetModel: String? = nil
    @Published public var downloadTargetFilename: String? = nil
    @Published public var downloadError: String? = nil
    fileprivate var expertsQueue: [String] = []
    fileprivate var expertsTotal: Int = 0
    
    private var downloadTask: URLSessionDownloadTask? = nil
    private var downloadStartTime: Date? = nil
    private var lastBytesWritten: Int64 = 0
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    
    // Catalog of verified iOS-compatible models with direct Hugging Face endpoints
    public static let recommendedModels: [LocalModelFile] = [
        LocalModelFile(
            name: "MiniCPM-V 4.7 (35B-A3B LES Mobile)",
            filename: "MiniCPM-V-4_7-35B-A3B-mix_q3gud_im-les.gguf",
            sizeBytes: 1_662_732_800,
            isDownloaded: false,
            downloadUrl: "https://huggingface.co/tc-mb/MiniCPM-V-Apps-gguf/resolve/main/MiniCPM-V-4.7-35B-A3B/MiniCPM-V-4_7-35B-A3B-mix_q3gud_im-les.gguf",
            architecture: "Qwen3.5-MoE + LES SSD",
            activeParams: "3.5B / 35.2B Active",
            ramFootprint: "5.0–6.2 GB (Safe Metal Ceiling)",
            isMoE: true,
            isIncomplete: false,
            expectedSizeBytes: 1_662_732_800
        ),
        LocalModelFile(
            name: "MiniCPM-V 4.7 1B (Edge Dense 672MB)",
            filename: "MiniCPM-V-4_7-1B-Q4_K_M.gguf",
            sizeBytes: 672_003_680,
            isDownloaded: false,
            downloadUrl: "https://huggingface.co/openbmb/MiniCPM-V-4.7-1B-gguf/resolve/main/MiniCPM-V-4_7-1B-Q4_K_M.gguf",
            architecture: "SigLIP M-RoPE + Qwen3.5 Dense",
            activeParams: "1.8B Dense",
            ramFootprint: "~1.1 GB (Instant)",
            isMoE: false,
            isIncomplete: false,
            expectedSizeBytes: 672_003_680
        )
    ]
    
    private override init() {
        let defaults = UserDefaults.standard
        let savedTemp = defaults.double(forKey: "local_llm_temp")
        self.temperature = savedTemp > 0 ? savedTemp : 0.7
        
        let savedTopP = defaults.double(forKey: "local_llm_top_p")
        self.topP = savedTopP > 0 ? savedTopP : 0.95
        
        let savedTopK = defaults.integer(forKey: "local_llm_top_k")
        self.topK = savedTopK > 0 ? savedTopK : 100
        
        let savedRep = defaults.double(forKey: "local_llm_rep_penalty")
        self.repetitionPenalty = savedRep > 0 ? savedRep : 1.03
        
        let savedCtx = defaults.integer(forKey: "local_llm_n_ctx")
        let initialCtx = savedCtx > 0 ? savedCtx : 4096
        self.contextLength = initialCtx
        self.activeContextMaxTokens = initialCtx
        
        let savedThreads = defaults.integer(forKey: "local_llm_n_threads")
        self.threadCount = savedThreads > 0 ? savedThreads : 4
        
        if defaults.object(forKey: "local_llm_les_enabled") == nil {
            self.lookaheadScheduling = true
        } else {
            self.lookaheadScheduling = defaults.bool(forKey: "local_llm_les_enabled")
        }
        
        if defaults.object(forKey: "local_llm_moe_window_c") == nil {
            self.moeCacheWindowC = 0 // Auto Optimal (c=48, ~5.3 GB Metal VRAM)
        } else {
            self.moeCacheWindowC = defaults.integer(forKey: "local_llm_moe_window_c")
        }
        
        // Upgrade default lookahead depth to 4 (OpenBMB's measured sweet spot when VRAM window is enabled)
        if defaults.object(forKey: "local_llm_moe_lookahead_d_v39") == nil {
            self.moeLookaheadDepth = 4
            defaults.set(4, forKey: "local_llm_moe_lookahead_d")
            defaults.set(true, forKey: "local_llm_moe_lookahead_d_v39")
        } else {
            let d = defaults.integer(forKey: "local_llm_moe_lookahead_d")
            self.moeLookaheadDepth = d > 0 ? d : 4
        }
        
        if defaults.object(forKey: "local_llm_moe_prewarm") == nil {
            self.moePrewarmLevel = 32
            defaults.set(32, forKey: "local_llm_moe_prewarm")
        } else {
            self.moePrewarmLevel = defaults.integer(forKey: "local_llm_moe_prewarm")
        }
        
        let savedKDecode = defaults.integer(forKey: "local_llm_moe_k_decode")
        self.moeKDecode = 8
        defaults.set(8, forKey: "local_llm_moe_k_decode")
        
        if defaults.object(forKey: "local_llm_dspark_enabled") == nil {
            self.isDSparkEnabled = false
        } else {
            self.isDSparkEnabled = defaults.bool(forKey: "local_llm_dspark_enabled")
        }
        
        let savedSpecN = defaults.integer(forKey: "local_llm_dspark_n_max")
        self.dsparkDraftNMax = (savedSpecN >= 1 && savedSpecN <= 8) ? savedSpecN : 2
        
        if defaults.object(forKey: "local_llm_flash_attn") == nil {
            self.flashAttention = true
        } else {
            self.flashAttention = defaults.bool(forKey: "local_llm_flash_attn")
        }
        
        if defaults.object(forKey: "local_llm_mtp_speculative") == nil {
            self.mtpSpeculative = true
        } else {
            self.mtpSpeculative = defaults.bool(forKey: "local_llm_mtp_speculative")
        }
        
        // Default KV Cache Quantization to 4-bit (q4_0) with LLAMA_ATTN_ROT_DISABLE=1 protection
        if defaults.object(forKey: "local_llm_kv_quant_v39") == nil {
            self.kvCacheQuant = "q4_0"
            defaults.set("q4_0", forKey: "local_llm_kv_quant")
            defaults.set(true, forKey: "local_llm_kv_quant_v39")
        } else {
            self.kvCacheQuant = defaults.string(forKey: "local_llm_kv_quant") ?? "q4_0"
        }
        
        if defaults.object(forKey: "local_llm_uncensored_lora") == nil {
            self.isUncensoredLoRAEnabled = true
        } else {
            self.isUncensoredLoRAEnabled = defaults.bool(forKey: "local_llm_uncensored_lora")
        }
        
        super.init()
        
        // One-time v42 stability & speed migration:
        // Set moeKDecode = 8 (p8d8), prewarmLevel = 16 (smooth start), dsparkDraftNMax = 2,
        // and reset window crash cap so user can explore full 9.5GB memory window.
        if defaults.object(forKey: "local_llm_safe_v42_migration") == nil {
            self.moeKDecode = 8
            defaults.set(8, forKey: "local_llm_moe_k_decode")
            self.moePrewarmLevel = 16
            defaults.set(16, forKey: "local_llm_moe_prewarm")
            self.dsparkDraftNMax = 2
            defaults.set(2, forKey: "local_llm_dspark_n_max")
            OpenBMBLlamaEngine.resetWindowCrashCap()
            defaults.set(true, forKey: "local_llm_safe_v42_migration")
        }
        
        updateMemoryMetrics()
        scanModels()
    }
    
    // MARK: - Memory & Context Telemetry
    public func updateMemoryMetrics() {
        self.availableMemoryBytes = UInt64(os_proc_available_memory())
        
        var physFootprint: UInt64 = 0
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            physFootprint = UInt64(info.phys_footprint)
        }
        
        var metalBytes: UInt64 = 0
        if let dev = MTLCreateSystemDefaultDevice() {
            metalBytes = UInt64(dev.currentAllocatedSize)
        }
        self.metalAllocatedBytes = metalBytes
        // Report the higher of Mach phys_footprint and active Metal unified buffer allocation so GPU-mapped expert windows are always visible
        self.residentMemoryBytes = max(physFootprint, metalBytes)
    }
    
    public func resetLocalSessionContext() {
        self.activeContextUsedTokens = 0
        self.activeContextCachedTokens = 0
        self.activeContextMaxTokens = self.contextLength
        Task {
            await OpenBMBLlamaEngine.shared.resetSession()
        }
    }
    
    public var ramUsageRatio: Double {
        guard jetsamLimitBytes > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(residentMemoryBytes) / Double(jetsamLimitBytes)))
    }
    
    public func formattedMemoryString(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024.0 * 1024.0 * 1024.0)
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / (1024.0 * 1024.0)
        return String(format: "%.0f MB", mb)
    }
    
    public var availableMemoryFormatted: String {
        let gb = Double(availableMemoryBytes) / (1024.0 * 1024.0 * 1024.0)
        return String(format: "%.1f GB Headroom", gb)
    }
    
    public var residentMemoryFormatted: String {
        let mb = Double(residentMemoryBytes) / (1024.0 * 1024.0)
        if mb >= 1024.0 {
            return String(format: "%.2f GB Used", mb / 1024.0)
        }
        return String(format: "%.0f MB Used", mb)
    }
    
    // MARK: - Model Discovery & Files App Integration
    public var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    public func scanModels() {
        updateMemoryMetrics()
        var list: [LocalModelFile] = []
        let fm = FileManager.default
        let docDir = documentsDirectory
        
        let modelsDir = docDir.appendingPathComponent("models", isDirectory: true)
        if !fm.fileExists(atPath: modelsDir.path) {
            try? fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
        
        let searchDirs = [docDir, modelsDir]
        var foundFilenames = Set<String>()
        
        for dir in searchDirs {
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                continue
            }
            for fileUrl in contents {
                let ext = fileUrl.pathExtension.lowercased()
                if ext == "gguf" || ext == "bin" {
                    let filename = fileUrl.lastPathComponent
                    let size = (try? fileUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    
                    // Don't treat standalone LoRA adapters, mmproj vision towers, or DSpark draft weights as base LLM models
                    if filename.localizedCaseInsensitiveContains("lora")
                        || filename.localizedCaseInsensitiveContains("mmproj")
                        || filename.localizedCaseInsensitiveContains("dspark") {
                        continue
                    }
                    
                    // Automatically prune 0-byte or trivial stubs (< 50MB)
                    if size < 50_000_000 {
                        try? fm.removeItem(at: fileUrl)
                        continue
                    }
                    
                    foundFilenames.insert(filename)
                    let isMiniCPM = filename.localizedCaseInsensitiveContains("minicpm")
                    let is35B = filename.localizedCaseInsensitiveContains("35b") || filename.localizedCaseInsensitiveContains("a3b")
                    
                    let recMatch = Self.recommendedModels.first(where: { $0.filename.lowercased() == filename.lowercased() })
                    let expectedSize = recMatch?.sizeBytes ?? 0
                    let isIncomplete = (expectedSize > 0 && Int64(size) < Int64(Double(expectedSize) * 0.85))
                    
                    let modelName: String
                    if let match = recMatch {
                        modelName = match.name
                    } else if isMiniCPM {
                        if is35B {
                            if filename.localizedCaseInsensitiveContains("les") {
                                modelName = "MiniCPM-V 4.7 (35B-A3B LES Mobile)"
                            } else {
                                modelName = "MiniCPM-V 4.7 (35B-A3B)"
                            }
                        } else if filename.localizedCaseInsensitiveContains("1b") {
                            modelName = "MiniCPM-V 4.7 1B (Edge Dense 672MB)"
                        } else {
                            modelName = "MiniCPM-V"
                        }
                    } else {
                        modelName = filename
                    }
                    
                    let model = LocalModelFile(
                        name: modelName,
                        filename: filename,
                        sizeBytes: Int64(size),
                        isDownloaded: !isIncomplete,
                        downloadUrl: recMatch?.downloadUrl,
                        architecture: isMiniCPM ? (is35B ? "Qwen3.5-MoE + LES SSD" : "MiniCPM Dense") : "Custom GGUF",
                        activeParams: is35B ? "3.5B / 35.2B Active" : "1.8B Dense",
                        ramFootprint: is35B ? estimatedVRAMCacheString(for: moeCacheWindowC) : String(format: "%.1f GB", Double(size) / (1024.0 * 1024.0 * 1024.0)),
                        isMoE: is35B,
                        isIncomplete: isIncomplete,
                        expectedSizeBytes: expectedSize > 0 ? expectedSize : Int64(size)
                    )
                    list.append(model)
                }
            }
        }
        
        for rec in Self.recommendedModels {
            if !foundFilenames.contains(rec.filename) {
                list.append(rec)
            }
        }
        
        self.availableModels = list
        self.isLoRADownloaded = (bundledLESLoRAURL != nil) || fm.fileExists(atPath: loraFileURL.path)
        let mmprojSize = (try? fm.attributesOfItem(atPath: visionProjectorFileURL.path)[.size] as? Int64) ?? 0
        self.isVisionProjectorDownloaded = mmprojSize > 500_000_000
        let dsparkSize = (try? fm.attributesOfItem(atPath: dsparkDraftFileURL.path)[.size] as? Int64) ?? 0
        self.isDSparkDownloaded = dsparkSize > 200_000_000
        
        let validDownloaded = list.filter { $0.isDownloaded && !$0.isIncomplete }
        let savedFilename = UserDefaults.standard.string(forKey: "local_llm_active_model_filename")
        
        if let savedFilename = savedFilename,
           let match = validDownloaded.first(where: { $0.filename == savedFilename }) {
            self.activeModel = match
        } else if let currentActive = self.activeModel,
                  validDownloaded.contains(where: { $0.filename == currentActive.filename }) {
            // Keep current active model
        } else {
            self.activeModel = validDownloaded.first ?? list.first
            if let firstValid = validDownloaded.first {
                UserDefaults.standard.set(firstValid.filename, forKey: "local_llm_active_model_filename")
            }
        }
    }
    
    public func selectActiveModel(_ model: LocalModelFile) {
        guard model.isDownloaded && !model.isIncomplete else { return }
        if self.activeModel?.filename == model.filename { return }
        
        if self.isModelLoadedInMemory {
            unloadActiveModel()
        }
        
        self.activeModel = model
        self.isOfflineFallbackActive = false
        UserDefaults.standard.set(model.filename, forKey: "local_llm_active_model_filename")
        if model.filename.localizedCaseInsensitiveContains("les") && !expertsComplete && !isDownloading {
            startDownloadExperts()
        }
    }
    
    public func importModel(from url: URL) async throws {
        guard url.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "LocalInference", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied for selected file."])
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let filename = url.lastPathComponent
        let dest = documentsDirectory.appendingPathComponent(filename)
        
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        
        try FileManager.default.copyItem(at: url, to: dest)
        await MainActor.run {
            self.scanModels()
        }
    }
    
    public func deleteModel(filename: String) {
        Task {
            await OpenBMBLlamaEngine.shared.unload()
            await NativeLlamaEngine.shared.unload()
            await MainActor.run {
                self.isModelLoadedInMemory = false
            }
        }
        let dest1 = documentsDirectory.appendingPathComponent(filename)
        let dest2 = documentsDirectory.appendingPathComponent("models").appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: dest1)
        try? FileManager.default.removeItem(at: dest2)
        
        if activeModel?.filename == filename {
            self.activeModel = nil
            UserDefaults.standard.removeObject(forKey: "local_llm_active_model_filename")
        }
        
        scanModels()
    }
    
    // MARK: - Manual Model Preheat & Memory Management
    public func preloadActiveModel() {
        guard !isLoadingModel else { return }
        guard let model = (activeModel?.isDownloaded == true && activeModel?.isIncomplete == false)
                ? activeModel
                : availableModels.first(where: { $0.isDownloaded && !$0.isIncomplete }) else { return }
        let modelPath = documentsDirectory.appendingPathComponent(model.filename).path
        let expertsDir = expertsDirectoryURL.path
        let isLESModel = model.filename.localizedCaseInsensitiveContains("les")
        let hasExperts = isLESModel && expertsComplete
        if isLESModel && !hasExperts {
            if !isDownloading { startDownloadExperts() }
            return
        }
        let mmprojPath = isLESModel ? visionProjectorFileURL.path : visionProjector1BFileURL.path
        let hasMMProj = FileManager.default.fileExists(atPath: mmprojPath)
        let activeLoRAPath: String? = (isUncensoredLoRAEnabled && isLoRADownloaded) ? loraFileURL.path : nil
        let activeDraftPath: String? = (isLESModel && isDSparkEnabled && isDSparkDownloaded) ? dsparkDraftFileURL.path : nil
        let effectiveSpecNMax = (activeDraftPath != nil) ? dsparkDraftNMax : 0
        let effectiveLookahead = lookaheadScheduling ? moeLookaheadDepth : 0
        let kvQuantInt = kvQuantTypeInt
        let kDecode = moeKDecode
        
        self.isLoadingModel = true
        self.hasPendingEngineReload = false
        
        Task {
            do {
                try await OpenBMBLlamaEngine.shared.loadModel(
                    modelPath: modelPath,
                    mmprojPath: hasMMProj ? mmprojPath : nil,
                    moeExpertsPath: hasExperts ? expertsDir : nil,
                    draftModelPath: activeDraftPath,
                    loraPath: activeLoRAPath,
                    contextLength: contextLength,
                    threadCount: threadCount,
                    temperature: Float(temperature),
                    cacheWindowC: moeCacheWindowC,
                    lookaheadDepth: effectiveLookahead,
                    prewarmLevel: moePrewarmLevel,
                    kvQuantType: kvQuantInt,
                    moeKDecode: kDecode,
                    specDraftNMax: effectiveSpecNMax
                )
                let telemetry = await OpenBMBLlamaEngine.shared.getContextTelemetry()
                await MainActor.run {
                    self.isLoadingModel = false
                    self.isModelLoadedInMemory = true
                    self.isOfflineFallbackActive = false
                    self.activeContextUsedTokens = telemetry.usedTokens
                    self.activeContextMaxTokens = telemetry.maxTokens > 0 ? telemetry.maxTokens : self.contextLength
                    self.updateMemoryMetrics()
                }
            } catch {
                print("[LocalInferenceEngine] OpenBMB Engine load notice: \(error). Trying NativeLlamaEngine...")
                if isLESModel {
                    await MainActor.run {
                        self.isLoadingModel = false
                        self.isModelLoadedInMemory = false
                        self.updateMemoryMetrics()
                    }
                    return
                }
                do {
                    try await NativeLlamaEngine.shared.loadModel(
                        filePath: modelPath,
                        contextLength: contextLength,
                        threadCount: threadCount,
                        flashAttention: flashAttention,
                        mtpSpeculative: mtpSpeculative,
                        kvCacheQuant: kvCacheQuant,
                        loraPath: activeLoRAPath
                    )
                    await MainActor.run {
                        self.isLoadingModel = false
                        self.isModelLoadedInMemory = true
                        self.isOfflineFallbackActive = false
                        self.updateMemoryMetrics()
                    }
                } catch {
                    print("[LocalInferenceEngine] Native llama load notice: \(error)")
                    await MainActor.run {
                        self.isLoadingModel = false
                        self.isModelLoadedInMemory = false
                        self.isOfflineFallbackActive = false
                        self.updateMemoryMetrics()
                    }
                }
            }
        }
    }
    
    public func unloadActiveModel() {
        Task {
            await OpenBMBLlamaEngine.shared.unload()
            await NativeLlamaEngine.shared.unload()
            await MainActor.run {
                self.isLoadingModel = false
                self.hasPendingEngineReload = false
                self.isModelLoadedInMemory = false
                self.isOfflineFallbackActive = false
                self.activeContextUsedTokens = 0
                self.activeContextCachedTokens = 0
                self.updateMemoryMetrics()
            }
        }
    }
    
    // MARK: - Vision Projector (mmproj-v47.gguf), DSpark Speculative Draft & Optional LoRA Downloaders
    public func startDownloadDSparkDraft() {
        let dsparkUrlStr = "https://huggingface.co/openbmb/MiniCPM-V-4.7-35B-A3B-DSpark-gguf/resolve/main/dspark-MiniCPM-V-4_7-35B-A3B-Q8_0.gguf"
        guard let url = URL(string: dsparkUrlStr), !isDownloading else { return }
        self.isDownloading = true
        self.downloadProgress = 0.0
        self.downloadTargetModel = "DSpark Speculative Draft (405 MB)"
        self.downloadTargetFilename = "dspark-MiniCPM-V-4_7-35B-A3B-Q8_0.gguf"
        self.downloadError = nil
        self.downloadStartTime = Date()
        self.lastBytesWritten = 0
        
        self.downloadTask = urlSession.downloadTask(with: url)
        self.downloadTask?.resume()
    }
    
    public func deleteDSparkDraft() {
        self.isDSparkEnabled = false
        try? FileManager.default.removeItem(at: dsparkDraftFileURL)
        scanModels()
        if isModelLoadedInMemory {
            preloadActiveModel()
        }
    }
    
    public func startDownloadVisionProjector() {
        let mmprojUrlStr = "https://huggingface.co/tc-mb/MiniCPM-V-Apps-gguf/resolve/main/MiniCPM-V-4.7-35B-A3B/mmproj-model-f16.gguf"
        guard let url = URL(string: mmprojUrlStr), !isDownloading else { return }
        self.isDownloading = true
        self.downloadProgress = 0.0
        self.downloadTargetModel = "35B Vision Tower (1.12 GB)"
        self.downloadTargetFilename = "mmproj-v47.gguf"
        self.downloadError = nil
        self.downloadStartTime = Date()
        self.lastBytesWritten = 0
        
        self.downloadTask = urlSession.downloadTask(with: url)
        self.downloadTask?.resume()
    }
    
    public func deleteVisionProjector() {
        try? FileManager.default.removeItem(at: visionProjectorFileURL)
        scanModels()
        if isModelLoadedInMemory {
            preloadActiveModel()
        }
    }
    
    public func startDownloadLoRA() {
        if bundledLESLoRAURL != nil {
            self.isLoRADownloaded = true
            self.isUncensoredLoRAEnabled = true
            return
        }
        let loraUrlStr = "https://huggingface.co/AtomicChat/MiniCPM-V-4.7-35B-A3B-Uncensored-GGUF/resolve/main/lora/MiniCPM-V-4.7-35B-A3B-Uncensored-LoRA.gguf"
        guard let url = URL(string: loraUrlStr) else { return }
        self.isDownloading = true
        self.downloadProgress = 0.0
        self.downloadTargetModel = "Uncensored LoRA"
        self.downloadTargetFilename = "MiniCPM-V-4.7-35B-A3B-Uncensored-LoRA.gguf"
        self.downloadError = nil
        self.downloadStartTime = Date()
        self.lastBytesWritten = 0
        
        self.downloadTask = urlSession.downloadTask(with: url)
        self.downloadTask?.resume()
    }
    
    public func deleteLoRA() {
        self.isUncensoredLoRAEnabled = false
        let docLoRA = documentsDirectory.appendingPathComponent("MiniCPM-V-4.7-35B-A3B-Uncensored-LoRA.gguf")
        try? FileManager.default.removeItem(at: docLoRA)
        scanModels()
    }
    
    // MARK: - Direct Cloud & Wi-Fi Downloader
    public func startDownload(model: LocalModelFile) {
        guard let urlStr = model.downloadUrl, let url = URL(string: urlStr) else { return }
        self.isDownloading = true
        self.downloadProgress = 0.0
        self.downloadTargetModel = model.name
        self.downloadTargetFilename = model.filename
        self.downloadError = nil
        self.downloadStartTime = Date()
        self.lastBytesWritten = 0
        
        self.downloadTask = urlSession.downloadTask(with: url)
        self.downloadTask?.resume()
    }
    
    public func cancelDownload() {
        self.expertsQueue = []
        self.downloadTask?.cancel()
        self.downloadTask = nil
        self.isDownloading = false
        self.downloadProgress = 0.0
        self.downloadTargetModel = nil
        self.downloadTargetFilename = nil
    }
    
    // URLSessionDownloadDelegate
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        self.downloadProgress = progress
        
        if let start = downloadStartTime {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 0.5 {
                let speedMB = (Double(totalBytesWritten) / (1024.0 * 1024.0)) / elapsed
                self.downloadSpeed = String(format: "%.1f MB/s", speedMB)
            }
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let attr = try? FileManager.default.attributesOfItem(atPath: location.path)
        let size = (attr?[.size] as? Int64) ?? 0
        
        if let name = downloadTargetFilename, name.hasPrefix("experts/") {
            let shard = String(name.dropFirst("experts/".count))
            let isManifest = shard == "manifest.json"
            guard size > (isManifest ? 1_000 : 100_000_000) else {
                self.downloadError = "Expert shard \(shard) download failed (bad response)."
                self.isDownloading = false
                self.expertsQueue = []
                return
            }
            try? FileManager.default.createDirectory(at: expertsDirectoryURL, withIntermediateDirectories: true)
            let dest = expertsDirectoryURL.appendingPathComponent(shard)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.moveItem(at: location, to: dest)
            downloadNextExpert()
            return
        }
        
        guard size > 50_000_000 else {
            self.downloadError = "Download failed: received invalid response or empty file (less than 50MB)."
            self.isDownloading = false
            self.downloadTargetModel = nil
            self.downloadTargetFilename = nil
            return
        }
        
        let filename = downloadTargetFilename ?? "MiniCPM-V-4_7-35B-A3B-mix_q3gud_im-les.gguf"
        let dest = documentsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: location, to: dest)
        
        self.isDownloading = false
        self.downloadProgress = 1.0
        self.downloadTargetModel = nil
        self.downloadTargetFilename = nil
        if filename.localizedCaseInsensitiveContains("lora") {
            self.isLoRADownloaded = true
            self.isUncensoredLoRAEnabled = true
        } else if filename.localizedCaseInsensitiveContains("dspark") {
            self.isDSparkDownloaded = true
            self.isDSparkEnabled = true
            if isModelLoadedInMemory {
                preloadActiveModel()
            }
        } else if filename.localizedCaseInsensitiveContains("mmproj") {
            self.isVisionProjectorDownloaded = true
            if isModelLoadedInMemory {
                preloadActiveModel()
            }
        } else {
            UserDefaults.standard.set(filename, forKey: "local_llm_active_model_filename")
        }
        scanModels()
        if filename.localizedCaseInsensitiveContains("les") && !expertsComplete {
            startDownloadExperts()
        }
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            self.downloadError = error.localizedDescription
            self.isDownloading = false
            self.expertsQueue = []
        }
    }
    
    // MARK: - LES Expert Shards (experts/manifest.json + layer_000...039.bin, ~13.8 GB)
    public static let expertFileNames: [String] =
        ["manifest.json"] + (0..<40).map { String(format: "layer_%03d.bin", $0) }
    private static let expertsBaseURL = "https://huggingface.co/tc-mb/MiniCPM-V-Apps-gguf/resolve/main/MiniCPM-V-4.7-35B-A3B/experts/"
    
    public var expertsDirectoryURL: URL { documentsDirectory.appendingPathComponent("experts") }
    
    private func expertShardPresent(_ name: String) -> Bool {
        let p = expertsDirectoryURL.appendingPathComponent(name).path
        let size = (try? FileManager.default.attributesOfItem(atPath: p)[.size] as? Int64) ?? 0
        return name == "manifest.json" ? size > 1_000 : size > 300_000_000
    }
    
    public func expertsPresentCount() -> Int {
        Self.expertFileNames.filter { expertShardPresent($0) }.count
    }
    
    public var expertsComplete: Bool {
        expertsPresentCount() == Self.expertFileNames.count
    }
    
    public func startDownloadExperts() {
        guard !isDownloading else { return }
        expertsQueue = Self.expertFileNames.filter { !expertShardPresent($0) }
        expertsTotal = Self.expertFileNames.count
        downloadError = nil
        downloadNextExpert()
    }
    
    fileprivate func downloadNextExpert() {
        guard let next = expertsQueue.first else {
            isDownloading = false
            downloadProgress = 1.0
            downloadTargetModel = nil
            downloadTargetFilename = nil
            return
        }
        expertsQueue.removeFirst()
        guard let url = URL(string: Self.expertsBaseURL + next) else { return }
        isDownloading = true
        downloadProgress = 0.0
        downloadTargetModel = "35B LES experts \(expertsTotal - expertsQueue.count)/\(expertsTotal)"
        downloadTargetFilename = "experts/" + next
        downloadStartTime = Date()
        lastBytesWritten = 0
        downloadTask = urlSession.downloadTask(with: url)
        downloadTask?.resume()
    }
    
    // MARK: - Local Conversations Store (Offline persistence)
    private var localChatsStorageURL: URL {
        documentsDirectory.appendingPathComponent("local_conversations.json")
    }
    
    public func loadLocalChats() -> [ChatSummary] {
        guard let data = try? Data(contentsOf: localChatsStorageURL),
              let list = try? JSONDecoder().decode([ChatSummary].self, from: data) else {
            return []
        }
        return list
    }
    
    public func saveLocalChat(summary: ChatSummary, messages: [ChatMessage]) {
        var chats = loadLocalChats()
        if let idx = chats.firstIndex(where: { $0.id == summary.id }) {
            chats[idx] = summary
        } else {
            chats.insert(summary, at: 0)
        }
        if let data = try? JSONEncoder().encode(chats) {
            try? data.write(to: localChatsStorageURL)
        }
        
        let msgFile = documentsDirectory.appendingPathComponent("chat_\(summary.id).json")
        if let msgData = try? JSONEncoder().encode(messages) {
            try? msgData.write(to: msgFile)
        }
    }
    
    public func loadLocalMessages(chatId: String) -> [ChatMessage] {
        let msgFile = documentsDirectory.appendingPathComponent("chat_\(chatId).json")
        guard let data = try? Data(contentsOf: msgFile),
              let msgs = try? JSONDecoder().decode([ChatMessage].self, from: data) else {
            return []
        }
        return msgs
    }
    
    public func deleteLocalChat(id: String) {
        var chats = loadLocalChats()
        chats.removeAll(where: { $0.id == id })
        if let data = try? JSONEncoder().encode(chats) {
            try? data.write(to: localChatsStorageURL)
        }
        let msgFile = documentsDirectory.appendingPathComponent("chat_\(id).json")
        try? FileManager.default.removeItem(at: msgFile)
    }
    
    public func renameLocalChat(id: String, newTitle: String) {
        var chats = loadLocalChats()
        if let idx = chats.firstIndex(where: { $0.id == id }) {
            chats[idx].title = newTitle
            if let data = try? JSONEncoder().encode(chats) {
                try? data.write(to: localChatsStorageURL)
            }
        }
    }
    
    // MARK: - On-Device Inference Stream
    public func generateStream(
        sessionId: String? = nil,
        prompt: String,
        images: [String],
        onToken: @escaping (String) -> Void
    ) async throws -> MessageMeta {
        updateMemoryMetrics()
        let startTime = Date()
        
        let targetModel = (activeModel?.isDownloaded == true && activeModel?.isIncomplete == false)
            ? activeModel
            : availableModels.first(where: { $0.isDownloaded && !$0.isIncomplete })
        
        if let model = targetModel {
            let modelPath = documentsDirectory.appendingPathComponent(model.filename).path
            let expertsDir = expertsDirectoryURL.path
            let isLESModel = model.filename.localizedCaseInsensitiveContains("les")
            let hasExperts = isLESModel && expertsComplete
            
            if isLESModel && !hasExperts {
                if !isDownloading { startDownloadExperts() }
                let msg = "**LES expert shards are missing or incomplete.** The 35B LES model needs 13.8 GB of expert files (`experts/`, \(expertsPresentCount())/\(Self.expertFileNames.count) present). I've started downloading them. Keep the app open on Wi-Fi, then send your message again once the download finishes."
                for word in msg.components(separatedBy: " ") {
                    onToken(word + " ")
                    try? await Task.sleep(nanoseconds: 12_000_000)
                }
                return MessageMeta(tps: 0.0, ttft: 0.1, elapsed: Date().timeIntervalSince(startTime), thoughtS: nil, tokens: msg.count / 4, promptTokens: prompt.count / 4, cachedTokens: 0, maxContext: contextLength, variant: "System Diagnostic", model: model.name, finishReason: "error")
            }
            
            let mmprojPath = isLESModel ? visionProjectorFileURL.path : visionProjector1BFileURL.path
            let hasMMProj = FileManager.default.fileExists(atPath: mmprojPath)
            
            if !images.isEmpty && !hasMMProj && isLESModel {
                if !isDownloading {
                    startDownloadVisionProjector()
                }
            }
            
            let activeLoRAPath: String? = (isUncensoredLoRAEnabled && isLoRADownloaded) ? loraFileURL.path : nil
            let activeDraftPath: String? = (isLESModel && isDSparkEnabled && isDSparkDownloaded) ? dsparkDraftFileURL.path : nil
            let effectiveSpecNMax = (activeDraftPath != nil) ? dsparkDraftNMax : 0
            let effectiveLookahead = lookaheadScheduling ? moeLookaheadDepth : 0
            let kvQuantInt = kvQuantTypeInt
            let kDecode = moeKDecode
            
            var openBMBError: String? = nil
            var nativeError: String? = nil
            
            // 1. OpenBMB Lookahead Expert Scheduling Engine (native C++ & Metal)
            do {
                let priorTelemetry = await OpenBMBLlamaEngine.shared.getContextTelemetry()
                let priorTokens = priorTelemetry.usedTokens
                
                try await OpenBMBLlamaEngine.shared.loadModel(
                    modelPath: modelPath,
                    mmprojPath: hasMMProj ? mmprojPath : nil,
                    moeExpertsPath: hasExperts ? expertsDir : nil,
                    draftModelPath: activeDraftPath,
                    loraPath: activeLoRAPath,
                    contextLength: contextLength,
                    threadCount: threadCount,
                    temperature: Float(temperature),
                    cacheWindowC: moeCacheWindowC,
                    lookaheadDepth: effectiveLookahead,
                    prewarmLevel: moePrewarmLevel,
                    kvQuantType: kvQuantInt,
                    moeKDecode: kDecode,
                    specDraftNMax: effectiveSpecNMax
                )
                await MainActor.run {
                    self.hasPendingEngineReload = false
                    self.isModelLoadedInMemory = true
                    self.isOfflineFallbackActive = false
                    self.updateMemoryMetrics()
                }
                
                var streamedCount = 0
                let result = try await OpenBMBLlamaEngine.shared.generateStream(
                    sessionId: sessionId,
                    prompt: prompt,
                    imageBase64List: images,
                    onToken: { [weak self] piece in
                        onToken(piece)
                        streamedCount += 1
                        if streamedCount % 16 == 0 {
                            DispatchQueue.main.async {
                                self?.updateMemoryMetrics()
                            }
                        }
                    }
                )
                
                let elapsed = Date().timeIntervalSince(startTime)
                let tps = result.tps > 0 ? result.tps : (elapsed > 0 ? Double(result.tokenCount) / elapsed : 14.5)
                let uncensoredTag = (isUncensoredLoRAEnabled && isLoRADownloaded) ? " · Uncensored" : ""
                let dsparkTag = (effectiveSpecNMax > 0) ? " · DSpark" : ""
                let moeTag = hasExperts ? "LES MoE" : "Dense"
                
                let actualPromptTokens = max(1, result.nPast - result.tokenCount)
                let actualMaxCtx = result.nCtx > 0 ? result.nCtx : contextLength
                let reusedKV = (priorTokens > 0 && result.nPast > priorTokens) ? priorTokens : 0
                
                let totalMoeAccesses = result.moeHits + result.moeMisses
                let hitRate = totalMoeAccesses > 0 ? (Double(result.moeHits) / Double(totalMoeAccesses) * 100.0) : nil
                let specRate = result.specDrafted > 0 ? (Double(result.specAccepted) / Double(result.specDrafted) * 100.0) : nil
                let specTokensPerStep = result.specRounds > 0 ? (Double(result.specAccepted) / Double(result.specRounds)) : nil
                let currentC = UserDefaults.standard.integer(forKey: "les_last_window_c")
                
                await MainActor.run {
                    self.lastMoECacheHitRate = hitRate
                    self.lastDSparkAcceptanceRate = specRate
                    self.lastDSparkTokensPerStep = specTokensPerStep
                    self.lastResolvedWindowC = currentC > 0 ? currentC : 64
                    self.activeContextUsedTokens = result.nPast
                    self.activeContextMaxTokens = actualMaxCtx
                    self.activeContextCachedTokens = reusedKV
                    self.updateMemoryMetrics()
                }
                
                return MessageMeta(
                    tps: tps,
                    ttft: result.ttft,
                    elapsed: elapsed,
                    thoughtS: nil,
                    tokens: result.tokenCount,
                    promptTokens: actualPromptTokens,
                    cachedTokens: reusedKV,
                    maxContext: actualMaxCtx,
                    variant: "OpenBMB \(moeTag) (Apple A19 Pro\(dsparkTag)\(uncensoredTag))",
                    model: model.name,
                    finishReason: "stop"
                )
            } catch {
                openBMBError = error.localizedDescription
                print("[LocalInferenceEngine] OpenBMB LES execution notice: \(error). Falling back to NativeLlamaEngine...")
            }
            
            // 2. Fallback to NativeLlamaEngine for non-LES dense GGUF models
            do {
                if isLESModel { throw NSError(domain: "LocalInference", code: -3, userInfo: [NSLocalizedDescriptionKey: "Skipped: LES model only runs on the OpenBMB expert-streaming engine."]) }
                try await NativeLlamaEngine.shared.loadModel(
                    filePath: modelPath,
                    contextLength: contextLength,
                    threadCount: threadCount,
                    flashAttention: flashAttention,
                    mtpSpeculative: mtpSpeculative,
                    kvCacheQuant: kvCacheQuant,
                    loraPath: activeLoRAPath
                )
                await MainActor.run {
                    self.isModelLoadedInMemory = true
                    self.isOfflineFallbackActive = false
                }
                
                let result = try await NativeLlamaEngine.shared.generateStream(
                    prompt: prompt,
                    temperature: temperature,
                    topP: topP,
                    topK: topK,
                    repetitionPenalty: repetitionPenalty,
                    onToken: onToken
                )
                
                let elapsed = Date().timeIntervalSince(startTime)
                let tps = elapsed > 0 ? Double(result.tokenCount) / elapsed : 14.5
                let uncensoredTag = (isUncensoredLoRAEnabled && isLoRADownloaded) ? " · Uncensored" : ""
                let estPrompt = max(1, prompt.count / 4)
                
                await MainActor.run {
                    self.activeContextUsedTokens = estPrompt + result.tokenCount
                    self.activeContextMaxTokens = self.contextLength
                    self.updateMemoryMetrics()
                }
                
                return MessageMeta(
                    tps: tps,
                    ttft: result.ttft,
                    elapsed: elapsed,
                    thoughtS: nil,
                    tokens: result.tokenCount,
                    promptTokens: estPrompt,
                    cachedTokens: 0,
                    maxContext: contextLength,
                    variant: "On-Device Engine (Apple A19 Pro\(uncensoredTag))",
                    model: model.name,
                    finishReason: "stop"
                )
            } catch {
                nativeError = error.localizedDescription
                print("[NativeLlamaEngine] Model execution notice: \(error)")
            }
            
            await MainActor.run {
                self.isModelLoadedInMemory = false
                self.isOfflineFallbackActive = true
            }
            
            let isLes = model.filename.localizedCaseInsensitiveContains("les")
            let isDesktopMoE = model.isMoE && !isLes
            
            var diagText = """
            ⚠️ **Model Initialization Diagnostic for \(model.name)**
            
            """
            
            if isDesktopMoE {
                diagText += """
                **Why this model couldn't initialize on iOS:**
                You have selected a monolithic 35B Desktop GGUF (\(model.sizeFormatted)). iOS caps Metal buffers at ~8.5 GB, and mapping a file this large into memory needs the `extended-virtual-addressing` entitlement. Sideloaded apps signed with a free Apple ID lose that entitlement, so the mmap fails with "Cannot allocate memory".
                
                **How to Fix:**
                • **35B on this phone:** select **`MiniCPM-V 4.7 (35B-A3B LES Mobile)`**.
                • **Fast and light:** use **`MiniCPM-V 4.7 1B (Edge Dense 672MB)`**.
                """
            } else {
                diagText += """
                Could not initialize model weights into memory.
                
                *Diagnostic Details:*
                • OpenBMB: \(openBMBError ?? "Unknown error")
                • Native Llama: \(nativeError ?? "Unknown error")
                """
            }
            
            let words = diagText.components(separatedBy: " ")
            for word in words {
                onToken(word + " ")
                try? await Task.sleep(nanoseconds: 18_000_000)
            }
            
            return MessageMeta(
                tps: 0.0,
                ttft: 0.1,
                elapsed: Date().timeIntervalSince(startTime),
                thoughtS: nil,
                tokens: diagText.count / 4,
                promptTokens: prompt.count / 4,
                cachedTokens: 0,
                maxContext: contextLength,
                variant: "System Diagnostic",
                model: model.name,
                finishReason: "error"
            )
        } else {
            let guide = """
            📱 **MiniCPM-V 4.7 (35B-A3B) On-Device Ready**
            
            No local `.gguf` weights were found in your iPhone's **Strata Chat** document folder yet.
            
            Tap the Model header at the top and download **MiniCPM-V 4.7 (35B-A3B LES Mobile)** or **MiniCPM-V 4.7 1B (Edge Dense)**.
            """
            
            let words = guide.components(separatedBy: " ")
            for (i, word) in words.enumerated() {
                try await Task.sleep(nanoseconds: 25_000_000)
                onToken(i == 0 ? word : " " + word)
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            return MessageMeta(
                tps: 40.0,
                ttft: 0.05,
                elapsed: elapsed,
                thoughtS: nil,
                tokens: words.count,
                promptTokens: prompt.count / 4,
                cachedTokens: 0,
                maxContext: contextLength,
                variant: "Setup Guide",
                model: "MiniCPM-V Setup",
                finishReason: "stop"
            )
        }
    }
}
