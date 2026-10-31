import Foundation
import llama

public enum LlamaEngineError: LocalizedError {
    case fileNotFound(String)
    case modelLoadFailed(String)
    case contextInitFailed
    case tokenizeFailed
    case decodeFailed(Int32)
    case samplerInitFailed
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Model file not found at path: \(path)"
        case .modelLoadFailed(let detail):
            return "Failed to load GGUF model: \(detail)"
        case .contextInitFailed:
            return "Failed to initialize llama context with Metal acceleration"
        case .tokenizeFailed:
            return "Failed to tokenize prompt"
        case .decodeFailed(let code):
            return "llama_decode failed with error code: \(code)"
        case .samplerInitFailed:
            return "Failed to initialize sampler chain"
        }
    }
}

public final class LlamaLogCapture: @unchecked Sendable {
    public static let shared = LlamaLogCapture()
    private let lock = NSLock()
    private var _lastLog: String = ""
    
    public var lastLog: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _lastLog
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _lastLog = newValue
        }
    }
    
    public func record(text: String) {
        lock.lock()
        defer { lock.unlock() }
        if !text.isEmpty {
            // Prioritize specific error details over the generic trailing 'failed to load model'
            if text.localizedCaseInsensitiveContains("architecture") ||
               text.localizedCaseInsensitiveContains("unknown") ||
               text.localizedCaseInsensitiveContains("mmap") ||
               text.localizedCaseInsensitiveContains("memory") ||
               text.localizedCaseInsensitiveContains("allocate") ||
               text.localizedCaseInsensitiveContains("error loading model") {
                _lastLog = text
            } else if _lastLog.isEmpty || _lastLog.localizedCaseInsensitiveContains("failed to load model") {
                _lastLog = text
            }
        }
    }
}

private func globalLlamaLogCallback(level: ggml_log_level, text: UnsafePointer<CChar>?, userData: UnsafeMutableRawPointer?) {
    guard let text = text else { return }
    let msg = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
    if !msg.isEmpty && (msg.localizedCaseInsensitiveContains("error") ||
                        msg.localizedCaseInsensitiveContains("fail") ||
                        msg.localizedCaseInsensitiveContains("exceed") ||
                        msg.localizedCaseInsensitiveContains("cannot") ||
                        msg.localizedCaseInsensitiveContains("invalid") ||
                        msg.localizedCaseInsensitiveContains("unknown")) {
        LlamaLogCapture.shared.record(text: msg)
        print("[llama.cpp log] \(msg)")
    }
}

public actor NativeLlamaEngine {
    public static let shared = NativeLlamaEngine()
    
    private var model: OpaquePointer? = nil
    private var context: OpaquePointer? = nil
    private var vocab: OpaquePointer? = nil
    private var loraAdapter: OpaquePointer? = nil
    private var loadedModelPath: String? = nil
    private var loadedLoRAPath: String? = nil
    private var isBackendInitialized: Bool = false
    
    private init() {}
    
    public func ensureBackendInitialized() {
        if !isBackendInitialized {
            llama_backend_init()
            llama_log_set(globalLlamaLogCallback, nil)
            isBackendInitialized = true
        }
    }
    
    public func isLoaded() -> Bool {
        return model != nil && context != nil
    }
    
    public func isLoaded(path: String, loraPath: String? = nil) -> Bool {
        return model != nil && context != nil && loadedModelPath == path && loadedLoRAPath == loraPath
    }
    
    public func unload() {
        if let a = loraAdapter {
            llama_adapter_lora_free(a)
            loraAdapter = nil
        }
        if let c = context {
            llama_free(c)
            context = nil
        }
        if let m = model {
            llama_model_free(m)
            model = nil
        }
        vocab = nil
        loadedModelPath = nil
        loadedLoRAPath = nil
    }
    
    public func loadModel(
        filePath: String,
        contextLength: Int,
        threadCount: Int,
        flashAttention: Bool = true,
        mtpSpeculative: Bool = true,
        kvCacheQuant: String = "q8_0",
        loraPath: String? = nil
    ) throws {
        if isLoaded(path: filePath, loraPath: loraPath) {
            return
        }
        
        unload()
        ensureBackendInitialized()
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw LlamaEngineError.fileNotFound(filePath)
        }
        
        var mparams = llama_model_default_params()
        #if targetEnvironment(simulator)
        mparams.n_gpu_layers = 0
        #else
        // Offload all transformer layers to Apple Silicon GPU with Metal
        mparams.n_gpu_layers = 99
        #endif
        
        LlamaLogCapture.shared.record(text: "")
        
        var loadedModel = llama_model_load_from_file(filePath, mparams)
        
        // If GPU layer allocation failed (e.g. Unified Memory buffer limit hit on large GGUF), fallback to CPU
        if loadedModel == nil && mparams.n_gpu_layers > 0 {
            print("[NativeLlamaEngine] GPU layer allocation failed, retrying with CPU mmap (n_gpu_layers = 0)...")
            mparams.n_gpu_layers = 0
            loadedModel = llama_model_load_from_file(filePath, mparams)
        }
        
        guard let m = loadedModel else {
            let logMsg = LlamaLogCapture.shared.lastLog
            let reason = logMsg.isEmpty
                ? "Corrupt/truncated GGUF file or insufficient RAM headroom."
                : logMsg
            throw LlamaEngineError.modelLoadFailed("\(filePath)\n\nReason: \(reason)")
        }
        
        guard let v = llama_model_get_vocab(m) else {
            llama_model_free(m)
            throw LlamaEngineError.modelLoadFailed(filePath)
        }
        
        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(max(512, contextLength))
        cparams.n_batch = 512
        cparams.n_ubatch = 512
        cparams.n_threads = Int32(max(1, threadCount))
        cparams.n_threads_batch = Int32(max(1, threadCount))
        cparams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO
        
        // Dynamic KV Cache Quantization
        if kvCacheQuant == "q4_0" {
            cparams.type_k = GGML_TYPE_Q4_0
            cparams.type_v = GGML_TYPE_Q4_0
        } else if kvCacheQuant == "q8_0" {
            cparams.type_k = GGML_TYPE_Q8_0
            cparams.type_v = GGML_TYPE_Q8_0
        } else {
            cparams.type_k = GGML_TYPE_F16
            cparams.type_v = GGML_TYPE_F16
        }
        
        var initCtx = llama_init_from_model(m, cparams)
        if initCtx == nil && cparams.n_ctx > 1024 {
            print("[NativeLlamaEngine] Context init failed with n_ctx=\(cparams.n_ctx), retrying with n_ctx=1024...")
            cparams.n_ctx = 1024
            initCtx = llama_init_from_model(m, cparams)
        }
        guard let c = initCtx else {
            llama_model_free(m)
            throw LlamaEngineError.contextInitFailed
        }
        
        // Attach Uncensored Abliterated LoRA adapter if present
        if let lora = loraPath, FileManager.default.fileExists(atPath: lora) {
            if let adapter = llama_adapter_lora_init(m, lora) {
                self.loraAdapter = adapter
                var adapters: [OpaquePointer?] = [adapter]
                var scales: [Float] = [1.0]
                let res = llama_set_adapters_lora(c, &adapters, 1, &scales)
                if res != 0 {
                    print("[NativeLlamaEngine] LoRA attach returned code \(res), proceeding with base model")
                }
            } else {
                print("[NativeLlamaEngine] LoRA adapter init failed, proceeding with base model")
            }
        }
        
        self.model = m
        self.vocab = v
        self.context = c
        self.loadedModelPath = filePath
        self.loadedLoRAPath = loraPath
    }
    
    public func tokenize(text: String, addSpecial: Bool = true, parseSpecial: Bool = true) throws -> [llama_token] {
        guard let vocab = self.vocab else {
            throw LlamaEngineError.tokenizeFailed
        }
        let utf8 = Array(text.utf8CString)
        let textLen = Int32(utf8.count - 1)
        guard textLen > 0 else { return [] }
        
        var tokens = [llama_token](repeating: 0, count: max(Int(textLen) + 32, 128))
        var count = llama_tokenize(vocab, utf8, textLen, &tokens, Int32(tokens.count), addSpecial, parseSpecial)
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, utf8, textLen, &tokens, Int32(tokens.count), addSpecial, parseSpecial)
        }
        guard count >= 0 else {
            throw LlamaEngineError.tokenizeFailed
        }
        return Array(tokens.prefix(Int(count)))
    }
    
    public func tokenToPiece(token: llama_token) -> String {
        guard let vocab = self.vocab else { return "" }
        var buf = [CChar](repeating: 0, count: 64)
        var pieceLen = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, false)
        if pieceLen < 0 {
            buf = [CChar](repeating: 0, count: Int(-pieceLen) + 1)
            pieceLen = llama_token_to_piece(vocab, token, &buf, Int32(buf.count), 0, false)
        }
        if pieceLen > 0 {
            let data = Data(buf.prefix(Int(pieceLen)).map { UInt8(bitPattern: $0) })
            return String(data: data, encoding: .utf8) ?? ""
        }
        return ""
    }
    
    public func applyChatTemplate(prompt: String) -> String {
        guard let model = self.model else {
            return "<|im_start|>user\n\(prompt)<|im_end|>\n<|im_start|>assistant\n"
        }
        
        let tmpl = llama_model_chat_template(model, nil)
        
        let userRole = "user"
        let userContent = prompt
        
        let cUserRole = userRole.cString(using: .utf8)
        let cUserContent = userContent.cString(using: .utf8)
        
        return cUserRole.flatMap { r in
            cUserContent.flatMap { c in
                var messages = [
                    llama_chat_message(role: r, content: c)
                ]
                var buf = [CChar](repeating: 0, count: prompt.utf8.count * 3 + 256)
                let len = llama_chat_apply_template(tmpl, &messages, messages.count, true, &buf, Int32(buf.count))
                if len > 0 {
                    return String(cString: buf)
                }
                return nil
            }
        } ?? "<|im_start|>user\n\(prompt)<|im_end|>\n<|im_start|>assistant\n"
    }
    
    public func generateStream(
        prompt: String,
        temperature: Double,
        topP: Double,
        topK: Int,
        repetitionPenalty: Double,
        onToken: @escaping (String) -> Void
    ) async throws -> (tokenCount: Int, ttft: Double) {
        guard let model = self.model, let context = self.context, let vocab = self.vocab else {
            throw LlamaEngineError.contextInitFailed
        }
        
        // 1. Format prompt with model's native chat template
        let formattedPrompt = applyChatTemplate(prompt: prompt)
        let promptTokens = try tokenize(text: formattedPrompt, addSpecial: true, parseSpecial: true)
        
        guard !promptTokens.isEmpty else {
            throw LlamaEngineError.tokenizeFailed
        }
        
        // 2. Setup Sampler Chain
        let sparams = llama_sampler_chain_default_params()
        guard let sampler = llama_sampler_chain_init(sparams) else {
            throw LlamaEngineError.samplerInitFailed
        }
        defer {
            llama_sampler_free(sampler)
        }
        
        if repetitionPenalty > 1.0 {
            llama_sampler_chain_add(sampler, llama_sampler_init_penalties(64, Float(repetitionPenalty), 0.0, 0.0))
        }
        if topK > 0 {
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k(Int32(topK)))
        }
        if topP > 0.0 && topP < 1.0 {
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(Float(topP), 1))
        }
        if temperature > 0.0 {
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(Float(temperature)))
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 1...UInt32.max)))
        } else {
            llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        }
        
        // 3. Clear KV cache memory for new prompt
        if let mem = llama_get_memory(context) {
            llama_memory_clear(mem, true)
        }
        
        // 4. Allocate batch for prompt processing
        var batch = llama_batch_init(512, 0, 1)
        defer {
            llama_batch_free(batch)
        }
        
        let startEvalTime = Date()
        var ttft: Double = 0.0
        
        // Evaluate prompt tokens in chunks of 512
        for i in 0..<promptTokens.count {
            let isLast = (i == promptTokens.count - 1)
            let token = promptTokens[i]
            let pos = llama_pos(i)
            
            let idx = Int(batch.n_tokens)
            batch.token[idx] = token
            batch.pos[idx] = pos
            batch.n_seq_id[idx] = 1
            batch.seq_id[idx]?.pointee = 0
            batch.logits[idx] = isLast ? 1 : 0
            batch.n_tokens += 1
            
            if batch.n_tokens == 512 || isLast {
                let res = llama_decode(context, batch)
                if res != 0 {
                    throw LlamaEngineError.decodeFailed(res)
                }
                batch.n_tokens = 0
            }
        }
        
        // 5. Autoregressive Generation Loop
        var currentPos = llama_pos(promptTokens.count)
        var generatedTokens = 0
        let maxOutputTokens = 2048
        
        while generatedTokens < maxOutputTokens {
            if Task.isCancelled { break }
            
            let nextToken = llama_sampler_sample(sampler, context, -1)
            llama_sampler_accept(sampler, nextToken)
            
            if generatedTokens == 0 {
                ttft = Date().timeIntervalSince(startEvalTime)
            }
            
            if llama_vocab_is_eog(vocab, nextToken) {
                break
            }
            
            let piece = tokenToPiece(token: nextToken)
            if !piece.isEmpty {
                onToken(piece)
            }
            generatedTokens += 1
            
            // Feed single token back to decode
            batch.n_tokens = 0
            let idx = 0
            batch.token[idx] = nextToken
            batch.pos[idx] = currentPos
            batch.n_seq_id[idx] = 1
            batch.seq_id[idx]?.pointee = 0
            batch.logits[idx] = 1
            batch.n_tokens = 1
            
            currentPos += 1
            
            let res = llama_decode(context, batch)
            if res != 0 {
                break
            }
        }
        
        return (tokenCount: generatedTokens, ttft: ttft > 0 ? ttft : 0.2)
    }
}
