import Foundation
import os
import Darwin.Mach

public actor OpenBMBLlamaEngine {
    public static let shared = OpenBMBLlamaEngine()
    
    private var context: OpaquePointer? = nil
    private var loadedModelPath: String? = nil
    private var loadedExpertsPath: String? = nil
    private var loadedMMProjPath: String? = nil
    private var loadedDraftModelPath: String? = nil
    private var loadedLoRAPath: String? = nil
    private var loadedContextLength: Int = 0
    private var loadedCacheWindowC: Int = -1
    private var loadedPrewarmLevel: Int = -1
    private var loadedKVQuantType: Int = -1
    private var loadedMoEKDecode: Int = -1
    private var loadedSpecDraftNMax: Int = -1
    private var activeSessionId: String? = nil
    
    private init() {}
    
    public func isLoaded() -> Bool {
        return context != nil
    }
    
    public func isLoaded(
        path: String,
        mmprojPath: String?,
        loraPath: String?,
        contextLength: Int,
        cacheWindowC: Int,
        prewarmLevel: Int
    ) -> Bool {
        return context != nil
            && loadedModelPath == path
            && loadedMMProjPath == mmprojPath
            && loadedLoRAPath == loraPath
            && loadedContextLength == contextLength
            && loadedCacheWindowC == cacheWindowC
            && loadedPrewarmLevel == prewarmLevel
    }
    
    public func unload() {
        if let ctx = context {
            mb_mtmd_free(ctx)
            context = nil
            // Allow the iOS kernel & Metal driver to finish reclaiming the multi-GB MTLResidencySet
            // before a new model allocation starts or os_proc_available_memory() is queried.
            Thread.sleep(forTimeInterval: 0.30)
        }
        loadedModelPath = nil
        loadedExpertsPath = nil
        loadedMMProjPath = nil
        loadedDraftModelPath = nil
        loadedLoRAPath = nil
        loadedContextLength = 0
        loadedCacheWindowC = -1
        loadedPrewarmLevel = -1
        loadedKVQuantType = -1
        loadedMoEKDecode = -1
        loadedSpecDraftNMax = -1
        activeSessionId = nil
    }
    
    public func hotSwapLoRA(_ loraPath: String?) {
        guard let ctx = context else { return }
        let validLoRA: String? = {
            if let p = loraPath, FileManager.default.fileExists(atPath: p) { return p }
            return nil
        }()
        if loadedLoRAPath != validLoRA {
            let rc = mb_mtmd_apply_lora(ctx, validLoRA, 1.0)
            print("[OpenBMBLlamaEngine] Hot-swapped LoRA (\(validLoRA ?? "none")) -> rc=\(rc)")
            loadedLoRAPath = (rc == 0) ? validLoRA : nil
        }
    }
    
    public func resetSession() {
        if let ctx = context {
            _ = mb_mtmd_clean_kv_cache(ctx)
        }
        activeSessionId = nil
    }
    
    public func getContextTelemetry() -> (usedTokens: Int, maxTokens: Int) {
        guard let ctx = context else {
            return (0, 0)
        }
        let used = Int(mb_mtmd_get_n_past(ctx))
        let maxC = Int(mb_mtmd_get_n_ctx(ctx))
        return (max(0, used), max(0, maxC))
    }
    
    public func setLookaheadDepth(_ depth: Int) {
        guard let ctx = context else { return }
        _ = mb_mtmd_set_moe_lookahead_prefetch_depth(ctx, Int32(max(0, min(16, depth))))
    }
    
    public func loadModel(
        modelPath: String,
        mmprojPath: String? = nil,
        moeExpertsPath: String? = nil,
        draftModelPath: String? = nil,
        loraPath: String? = nil,
        contextLength: Int = 8192,
        threadCount: Int = 4,
        temperature: Float = 0.7,
        cacheWindowC: Int = 0, // 0 = auto optimal for device
        lookaheadDepth: Int = 4,
        prewarmLevel: Int = 32,
        kvQuantType: Int = 1, // 2 = Q4_0, 1 = Q8_0, 0 = F16
        moeKDecode: Int = 8,  // 8 = p8d8, 6 = fast, 4 = turbo p8d4
        specDraftNMax: Int = 0
    ) throws {
        let validMMProj: String? = {
            if let p = mmprojPath, FileManager.default.fileExists(atPath: p) { return p }
            return nil
        }()
        let validDraft: String? = {
            if specDraftNMax > 0, let p = draftModelPath, FileManager.default.fileExists(atPath: p) { return p }
            return nil
        }()
        let effectiveSpecNMax = (validDraft != nil) ? max(1, min(8, specDraftNMax)) : 0
        let validLoRA: String? = {
            if let p = loraPath, FileManager.default.fileExists(atPath: p) { return p }
            return nil
        }()
        
        let clampedCtx = max(2048, min(16384, contextLength))
        
        // If only LoRA or lookahead changed while the model is already loaded, hot-swap without reloading 35B weights!
        if let ctx = self.context,
           loadedModelPath == modelPath,
           loadedMMProjPath == validMMProj,
           loadedDraftModelPath == validDraft,
           loadedSpecDraftNMax == effectiveSpecNMax,
           loadedContextLength == clampedCtx,
           loadedCacheWindowC == cacheWindowC,
           loadedPrewarmLevel == prewarmLevel,
           loadedKVQuantType == kvQuantType,
           loadedMoEKDecode == moeKDecode {
            if loadedLoRAPath != validLoRA {
                let rc = mb_mtmd_apply_lora(ctx, validLoRA, 1.0)
                print("[OpenBMBLlamaEngine] Hot-swapped LoRA (\(validLoRA ?? "none")) -> rc=\(rc)")
                loadedLoRAPath = (rc == 0) ? validLoRA : nil
            }
            _ = mb_mtmd_set_moe_lookahead_prefetch_depth(ctx, Int32(max(0, min(16, lookaheadDepth))))
            return
        }
        
        unload()
        
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw NSError(domain: "OpenBMBLlamaEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file not found at: \(modelPath)"])
        }
        
        let isMoESSD = (moeExpertsPath?.isEmpty == false)
        
        var params = mb_mtmd_params_default()
        params.n_predict = 1024
        params.n_ctx = Int32(clampedCtx)
        params.n_threads = Int32(max(1, min(6, threadCount)))
        params.temperature = temperature
        params.use_gpu = true
        params.n_ubatch = isMoESSD ? 1024 : 512
        params.kv_quant_type = Int32(kvQuantType)
        params.moe_k_decode = Int32(max(4, min(8, moeKDecode)))
        params.spec_draft_n_max = Int32(effectiveSpecNMax)
        
        if isMoESSD {
            let lookahead = max(0, min(16, lookaheadDepth))
            params.moe_slot_bank = 256
            params.moe_lookahead_prefetch_depth = Int32(lookahead)
            let resolvedC = Self.resolveDecodeWindow(
                expertsPath: moeExpertsPath ?? "",
                requestedC: cacheWindowC,
                lookahead: lookahead,
                nCtx: clampedCtx,
                kvQuantType: kvQuantType,
                hasMMProj: validMMProj != nil,
                hasDSpark: effectiveSpecNMax > 0
            )
            params.moe_decode_window = Int32(resolvedC)
            // Clamp DSpark n_max so verification batch (n_max + 1) * moeKDecode fits inside the per-layer window (MiniCPMModelConst.effectiveSpecDraftNMax)
            if effectiveSpecNMax > 0 {
                let kUsed = max(4, min(8, moeKDecode))
                let maxRows = max(1, (resolvedC + lookahead) / kUsed)
                let maxNMax = max(0, maxRows - 1)
                params.spec_draft_n_max = Int32(min(effectiveSpecNMax, maxNMax))
            }
            // Prewarm up to min(48, resolvedC) from the K4-total-1 cluster table (triggered on prefill->decode transition)
            let effectivePrewarm = resolvedC > 0 ? min(48, min(prewarmLevel, resolvedC)) : 0
            params.moe_prewarm_level = Int32(effectivePrewarm)
            params.moe_prewarm_table_id = 1 // K4-total-1 cluster table
            
            UserDefaults.standard.set(Int(params.moe_decode_window), forKey: Self.lastWindowKey)
            UserDefaults.standard.synchronize()
            print("[OpenBMBLlamaEngine] MoE-SSD params: slot_bank=256 window_c=\(params.moe_decode_window) prewarm=\(params.moe_prewarm_level) lookahead=\(lookahead) kv_quant=\(kvQuantType) k_decode=\(params.moe_k_decode) dspark=\(params.spec_draft_n_max) n_ctx=\(params.n_ctx)")
        } else {
            params.moe_slot_bank = 0
            params.moe_decode_window = 0
            params.moe_lookahead_prefetch_depth = 0
            params.moe_prewarm_level = 0
        }
        
        var ctx: OpaquePointer?
        if let mmproj = validMMProj {
            ctx = mb_mtmd_init(modelPath, mmproj, moeExpertsPath, validDraft, &params)
            if ctx == nil && params.use_gpu && !isMoESSD {
                print("[OpenBMBLlamaEngine] GPU init failed, retrying with CPU...")
                params.use_gpu = false
                ctx = mb_mtmd_init(modelPath, mmproj, moeExpertsPath, validDraft, &params)
            }
        } else {
            ctx = mb_mtmd_init_text_only(modelPath, moeExpertsPath, validDraft, &params)
            if ctx == nil && params.use_gpu && !isMoESSD {
                print("[OpenBMBLlamaEngine] GPU text-only init failed, retrying with CPU...")
                params.use_gpu = false
                ctx = mb_mtmd_init_text_only(modelPath, moeExpertsPath, validDraft, &params)
            }
        }
        
        guard let validCtx = ctx else {
            let err = String(cString: mb_mtmd_last_init_error())
            let reason = err.isEmpty ? "Failed to initialize OpenBMB MTMD engine." : err
            throw NSError(domain: "OpenBMBLlamaEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: reason])
        }
        
        self.context = validCtx
        self.loadedModelPath = modelPath
        self.loadedExpertsPath = moeExpertsPath
        self.loadedMMProjPath = validMMProj
        self.loadedDraftModelPath = validDraft
        self.loadedSpecDraftNMax = effectiveSpecNMax
        self.loadedContextLength = clampedCtx
        self.loadedCacheWindowC = cacheWindowC
        self.loadedPrewarmLevel = prewarmLevel
        self.loadedKVQuantType = kvQuantType
        self.loadedMoEKDecode = moeKDecode
        
        // Dynamic Model Version (471 for 1B Dense, 47 for 35B MoE SSD, 46 for standard)
        let is1B = modelPath.localizedCaseInsensitiveContains("1b")
        let is35B = modelPath.localizedCaseInsensitiveContains("35b") || modelPath.localizedCaseInsensitiveContains("a3b")
        let version: Int32 = is1B ? 471 : (is35B ? 47 : 46)
        
        mb_mtmd_set_model_version(validCtx, version)
        mb_mtmd_set_enable_thinking(validCtx, false)
        
        if let lora = validLoRA {
            let rc = mb_mtmd_apply_lora(validCtx, lora, 1.0)
            print("[OpenBMBLlamaEngine] Initial LoRA attach (\(lora)) -> rc=\(rc)")
            self.loadedLoRAPath = (rc == 0) ? lora : nil
        } else {
            self.loadedLoRAPath = nil
        }
    }
    
    // MARK: - MoE-SSD decode window sizing
    private static let pendingKey = "les_load_pending"
    private static let lastWindowKey = "les_last_window_c"
    private static let capKey = "les_window_cap"
    
    public static func resetWindowCrashCap() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: capKey)
        ud.set(false, forKey: pendingKey)
        ud.synchronize()
    }
    
    private static func physicalGiB() -> Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    }
    
    private static func footprintBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }
    
    /// Average bytes of one expert slot (sum of routed FFN families), read from manifest.json.
    public static func bytesPerSlot(expertsPath: String) -> Int64? {
        let url = URL(fileURLWithPath: expertsPath).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["entries"] as? [[String: Any]] else { return nil }
        let routed: Set<String> = ["ffn_gate_exps", "ffn_up_exps", "ffn_down_exps", "ffn_gate_up_exps"]
        var perFamily: [String: (sum: Int64, n: Int64)] = [:]
        for e in entries {
            guard let fam = e["tensor_family"] as? String, routed.contains(fam) else { continue }
            let b = (e["bytes_per_expert"] as? NSNumber)?.int64Value ?? 0
            guard b > 0 else { continue }
            var cur = perFamily[fam] ?? (0, 0)
            cur.sum += b; cur.n += 1
            perFamily[fam] = cur
        }
        var total: Int64 = 0
        for (_, v) in perFamily where v.n > 0 { total += v.sum / v.n }
        return total > 0 ? total : nil
    }
    
    /// Per-layer cache window `c` (engine adds the lookahead slots on top).
    /// On 12 GB iPhones (iPhone 17 Pro), allows scaling `c` up to 128 on high headroom while honoring explicit user choices.
    public static func resolveDecodeWindow(
        expertsPath: String,
        requestedC: Int,
        lookahead: Int,
        nCtx: Int,
        kvQuantType: Int,
        hasMMProj: Bool,
        hasDSpark: Bool
    ) -> Int {
        let ud = UserDefaults.standard
        let gib = physicalGiB()
        let avail = Int64(os_proc_available_memory())
        let foot = footprintBytes()
        
        let deviceDefault: Int
        let deviceMax: Int
        let ceilingGiB: Double
        if gib >= 13.5 {
            deviceDefault = 128
            deviceMax = 128
            ceilingGiB = 12.0
        } else if gib >= 9.5 {
            deviceDefault = 64
            deviceMax = 128
            ceilingGiB = 9.5
        } else if gib >= 6.5 {
            deviceDefault = 32
            deviceMax = 64
            ceilingGiB = 6.0
        } else {
            deviceDefault = 16
            deviceMax = 32
            ceilingGiB = 4.5
        }
        
        // Crash recovery cap
        var cap = ud.object(forKey: capKey) != nil ? ud.integer(forKey: capKey) : Int.max
        if ud.bool(forKey: pendingKey) {
            let last = ud.integer(forKey: lastWindowKey)
            let reduced = last <= 24 ? 16 : max(24, ((last - 8) / 8) * 8)
            cap = min(cap, reduced)
            ud.set(cap, forKey: capKey)
            ud.set(false, forKey: pendingKey)
            print("[OpenBMBLlamaEngine] previous MoE session did not finish (window c=\(last)) -> capping window at c=\(cap)")
        }
        
        let targetC = requestedC > 0 ? min(requestedC, deviceMax) : deviceDefault
        var c = targetC
        
        if let bps = bytesPerSlot(expertsPath: expertsPath), bps > 0 {
            let ceiling = Int64(ceilingGiB * 1_073_741_824.0)
            let byCeiling = max(0, ceiling - foot)
            let headroom = avail > 0 ? min(avail, byCeiling) : byCeiling
            // V47 only has 10 KV layers: 20 KiB/tok at F16, ~10.6 KiB/tok at Q8_0, ~5.7 KiB/tok at Q4_0
            let bytesPerTok: Double = (kvQuantType == 2) ? 5_850.0 : ((kvQuantType == 1) ? 10_880.0 : 20_480.0)
            let kvExtraMiB = max(0, Int((Double(nCtx) * bytesPerTok / 1_048_576.0).rounded()) - 15)
            // mmproj is lazily unloaded right after init on MoE models, so baseReserveMiB is ~1850 MiB for text turns!
            let baseReserveMiB = 1850
            let dsparkReserveMiB = hasDSpark ? 450 : 0
            let reserve = Int64(baseReserveMiB + kvExtraMiB + dsparkReserveMiB) * 1_048_576
            let budget = headroom - reserve
            if budget > 0 {
                let totalSlots = budget / (bps * 40)
                let cacheSlots = Int(totalSlots) - lookahead
                let maxPossibleC = cacheSlots >= 16 ? (cacheSlots / 8) * 8 : 16
                // If the user explicitly requested a window, honor it up to budget; otherwise take targetC
                c = min(targetC, maxPossibleC)
            } else {
                c = min(targetC, 32)
            }
            let windowMiB = Int64(c + lookahead) * 40 * bps / 1_048_576
            print("[OpenBMBLlamaEngine] window budget: avail=\(avail / 1_048_576) MiB ceiling=\(ceiling / 1_048_576) MiB headroom=\(headroom / 1_048_576) MiB -> c=\(c) (\(windowMiB) MiB VRAM cache)")
        }
        return max(16, min(c, cap))
    }
    
    private func markSessionHealthy() {
        UserDefaults.standard.set(false, forKey: Self.pendingKey)
        UserDefaults.standard.synchronize()
    }
    
    public func generateStream(
        sessionId: String?,
        prompt: String,
        imageBase64List: [String] = [],
        onToken: @escaping (String) -> Void
    ) async throws -> (tokenCount: Int, ttft: Double, tps: Double, nPast: Int, nCtx: Int, specDrafted: Int, specAccepted: Int, specRounds: Int, moeHits: Int, moeMisses: Int) {
        guard let ctx = self.context else {
            throw NSError(domain: "OpenBMBLlamaEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "Engine context not initialized"])
        }
        
        let currentMaxCtx = Int(mb_mtmd_get_n_ctx(ctx))
        let currentNPast = Int(mb_mtmd_get_n_past(ctx))
        
        // Preserve multi-turn KV cache within the same conversation; wipe only on new chat or near overflow
        if let sid = sessionId, sid == activeSessionId, currentNPast > 0, (currentNPast + 512) < currentMaxCtx {
            // Keep KV cache for instant multi-turn continuation!
        } else {
            _ = mb_mtmd_clean_kv_cache(ctx)
            activeSessionId = sessionId
        }
        
        mb_mtmd_perf_reset(ctx)
        
        let startEvalTime = Date()
        var ttft: Double = 0.0
        
        if loadedExpertsPath != nil {
            UserDefaults.standard.set(true, forKey: Self.pendingKey)
            UserDefaults.standard.synchronize()
        }
        
        // If user attached an image and vision projector is loaded, decode base64 to temp file and prefill
        if let firstB64 = imageBase64List.first, loadedMMProjPath != nil {
            let cleanB64: String
            if let commaIdx = firstB64.firstIndex(of: ",") {
                cleanB64 = String(firstB64[firstB64.index(after: commaIdx)...])
            } else {
                cleanB64 = firstB64
            }
            if let imgData = Data(base64Encoded: cleanB64, options: .ignoreUnknownCharacters) {
                let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("strata_vision_input.jpg")
                try? imgData.write(to: tmpURL)
                let imgRes = mb_mtmd_prefill_image(ctx, tmpURL.path)
                if imgRes == 0 {
                    _ = mb_mtmd_prewarm_after_image(ctx)
                } else {
                    print("[OpenBMBLlamaEngine] Image prefill notice: \(String(cString: mb_mtmd_get_last_error(ctx)))")
                }
            }
        }
        
        // Prefill prompt
        let effectivePrompt = (prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !imageBase64List.isEmpty)
            ? "Describe this image."
            : prompt
        let prefillRes = mb_mtmd_prefill_text(ctx, effectivePrompt, "user")
        if prefillRes != 0 {
            UserDefaults.standard.set(false, forKey: Self.pendingKey)
            let err = String(cString: mb_mtmd_get_last_error(ctx))
            throw NSError(domain: "OpenBMBLlamaEngine", code: Int(prefillRes), userInfo: [NSLocalizedDescriptionKey: "Prefill failed: \(err)"])
        }
        
        var generatedTokens = 0
        let maxTokens = 2048
        
        while generatedTokens < maxTokens {
            if Task.isCancelled { break }
            
            let tokenStruct = mb_mtmd_loop(ctx)
            if generatedTokens == 0 {
                ttft = Date().timeIntervalSince(startEvalTime)
            }
            
            if tokenStruct.is_end {
                if let str = tokenStruct.token {
                    mb_mtmd_string_free(str)
                }
                break
            }
            
            if let cStr = tokenStruct.token {
                let piece = String(cString: cStr)
                mb_mtmd_string_free(tokenStruct.token)
                if !piece.isEmpty {
                    onToken(piece)
                }
            }
            
            generatedTokens += 1
            if generatedTokens == 1 { markSessionHealthy() }
        }
        
        let perf = mb_mtmd_perf_snapshot(ctx)
        let finalTps: Double
        if perf.decode_ms > 0 && perf.decode_tokens > 0 {
            finalTps = Double(perf.decode_tokens) / (perf.decode_ms / 1000.0)
        } else {
            let elapsed = Date().timeIntervalSince(startEvalTime)
            finalTps = elapsed > 0 ? Double(generatedTokens) / elapsed : 15.0
        }
        let finalTtft = perf.prefill_ms > 0 ? (perf.prefill_ms / 1000.0) : (ttft > 0 ? ttft : 0.15)
        let endNPast = Int(mb_mtmd_get_n_past(ctx))
        let endNCtx = Int(mb_mtmd_get_n_ctx(ctx))
        
        return (
            tokenCount: generatedTokens,
            ttft: finalTtft,
            tps: finalTps,
            nPast: endNPast,
            nCtx: endNCtx,
            specDrafted: Int(perf.spec_drafted),
            specAccepted: Int(perf.spec_accepted),
            specRounds: Int(perf.spec_rounds),
            moeHits: Int(perf.moe_hits),
            moeMisses: Int(perf.moe_misses)
        )
    }
}
