import Foundation

public enum Backend: String, Codable, CaseIterable, Identifiable {
    case strata = "strata"
    case hermes = "hermes"
    case local = "local"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .strata: return "Strata Direct"
        case .hermes: return "Hermes Agent"
        case .local: return "On-Device (MiniCPM)"
        }
    }
}

public enum EffortLevel: String, Codable, CaseIterable, Identifiable {
    case off = "off"
    case low = "low"
    case medium = "medium"
    case high = "high"
    case max = "max"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .max: return "Max"
        }
    }
    
    public var shortName: String {
        switch self {
        case .off: return "Off"
        case .low: return "Low"
        case .medium: return "Med"
        case .high: return "High"
        case .max: return "Max"
        }
    }
    
    public var iconName: String {
        switch self {
        case .off: return "brain.head.profile"
        case .low: return "tortoise"
        case .medium: return "brain"
        case .high: return "flame"
        case .max: return "bolt.shield"
        }
    }
}

public struct GPUInfo: Codable {
    public let usedMib: Double?
    public let totalMib: Double?
    public let name: String?
    public let tempC: Double?
    public let utilPct: Double?
    
    enum CodingKeys: String, CodingKey {
        case usedMib = "used_mib"
        case totalMib = "total_mib"
        case name
        case tempC = "temp_c"
        case utilPct = "util_pct"
    }
}

public struct ServerStatus: Codable {
    public let state: String
    public let busy: Bool?
    public let loadingSince: Double?
    public let switchTarget: String?
    public let variant: String?
    public let gpu: GPUInfo?
    public let idleUnloadMinutes: Int?
    public let buildId: Int?
    
    enum CodingKeys: String, CodingKey {
        case state
        case busy
        case loadingSince = "loading_since"
        case switchTarget = "switch_target"
        case variant
        case gpu
        case idleUnloadMinutes = "idle_unload_minutes"
        case buildId = "build_id"
    }
    
    public var variantDisplay: String {
        switch variant {
        case "swift-64k": return "Swift 1.5 64k (Ultra)"
        case "swift-128k": return "Swift 1.5 128k (Fast)"
        case "swift-160k": return "Swift 1.5 160k (Balanced)"
        case "swift": return "Swift 1.5 262k"
        case "original": return "Original GSQ 160k"
        default: return variant ?? "Original GSQ 160k"
        }
    }
}

public struct ChatSummary: Codable, Identifiable, Hashable {
    public let id: String
    public var title: String
    public let backend: String
    public let hermesSessionId: String?
    public let created: Double?
    public let updated: Double?
    public let preview: String?
    public let messageCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, title, backend
        case hermesSessionId = "hermes_session_id"
        case created, updated
        case preview
        case messageCount = "message_count"
    }
    
    public var updatedAt: Double {
        return updated ?? created ?? Date().timeIntervalSince1970
    }
    
    public init(id: String, title: String, backend: String, hermesSessionId: String? = nil, created: Double? = nil, updated: Double? = nil, preview: String? = nil, messageCount: Int? = nil) {
        self.id = id
        self.title = title
        self.backend = backend
        self.hermesSessionId = hermesSessionId
        self.created = created
        self.updated = updated
        self.preview = preview
        self.messageCount = messageCount
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = (try? c.decode(String.self, forKey: .title)) ?? "Chat"
        self.backend = (try? c.decode(String.self, forKey: .backend)) ?? "strata"
        self.hermesSessionId = try? c.decodeIfPresent(String.self, forKey: .hermesSessionId)
        self.created = try? c.decodeIfPresent(Double.self, forKey: .created)
        self.updated = try? c.decodeIfPresent(Double.self, forKey: .updated)
        self.preview = try? c.decodeIfPresent(String.self, forKey: .preview)
        self.messageCount = try? c.decodeIfPresent(Int.self, forKey: .messageCount)
    }
}

public struct ToolCall: Codable, Identifiable, Hashable {
    public var id: String
    public let name: String
    public var status: String // "running", "done", "error"
    
    public init(id: String = UUID().uuidString, name: String, status: String = "done") {
        self.id = id
        self.name = name
        self.status = status
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, tool, status
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        let decodedName = (try? c.decode(String.self, forKey: .name))
            ?? (try? c.decode(String.self, forKey: .tool))
            ?? "tool"
        self.name = decodedName
        self.status = (try? c.decode(String.self, forKey: .status)) ?? "done"
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(status, forKey: .status)
    }
}

public struct ApprovalPrompt: Codable, Hashable {
    public let id: String
    public let command: String?
    public let reason: String?
    public var resolved: String?
    
    public init(id: String, command: String?, reason: String?, resolved: String? = nil) {
        self.id = id
        self.command = command
        self.reason = reason
        self.resolved = resolved
    }
}

public struct ClarifyPrompt: Codable, Hashable {
    public let id: String
    public let question: String
    public let choices: [String]?
    public var resolved: String?
    
    public init(id: String, question: String, choices: [String]?, resolved: String? = nil) {
        self.id = id
        self.question = question
        self.choices = choices
        self.resolved = resolved
    }
}

public struct MessageSegment: Codable, Hashable {
    public let kind: String   // "reasoning" or "content"
    public let text: String
}

// PC telemetry from `GET /api/hardware`. Every number here comes from a real sensor; a field
// the hardware does not expose arrives as nil and the sheet prints a dash rather than guessing.
public struct HardwareGPUInfo: Codable {
    public let index: Int?
    public let name: String?
    public let role: String?          // "primary" = the model card, "secondary" = the vision card
    public let tempC: Double?
    public let powerW: Double?
    public let powerLimitW: Double?
    public let utilPct: Double?
    public let vramUtilPct: Double?
    public let vramUsedMib: Double?
    public let vramTotalMib: Double?
    public let clockMhz: Double?
    public let clockMaxMhz: Double?
    public let pstate: String?

    enum CodingKeys: String, CodingKey {
        case index, name, role, pstate
        case tempC = "temp_c"
        case powerW = "power_w"
        case powerLimitW = "power_limit_w"
        case utilPct = "util_pct"
        case vramUtilPct = "vram_util_pct"
        case vramUsedMib = "vram_used_mib"
        case vramTotalMib = "vram_total_mib"
        case clockMhz = "clock_mhz"
        case clockMaxMhz = "clock_max_mhz"
    }
}

public struct HardwareCPUInfo: Codable {
    public let tempC: Double?
    public let ccdC: Double?
    public let load1m: Double?
    public let load5m: Double?
    public let load15m: Double?

    enum CodingKeys: String, CodingKey {
        case load1m = "load_1m"
        case load5m = "load_5m"
        case load15m = "load_15m"
        case tempC = "temp_c"
        case ccdC = "ccd_c"
    }
}

public struct HardwareMemoryInfo: Codable {
    public let totalMib: Double?
    public let availableMib: Double?
    public let usedMib: Double?
    public let usedPct: Double?
    public let swapUsedMib: Double?
    public let swapTotalMib: Double?

    enum CodingKeys: String, CodingKey {
        case totalMib = "total_mib"
        case availableMib = "available_mib"
        case usedMib = "used_mib"
        case usedPct = "used_pct"
        case swapUsedMib = "swap_used_mib"
        case swapTotalMib = "swap_total_mib"
    }
}

public struct HardwareBoardInfo: Codable {
    public let systemC: Double?
    public let vrmMosC: Double?
    public let pchC: Double?
    public let cpuSocketC: Double?
    public let fansRpm: [String: Double]?
    public let railsV: [String: Double]?

    enum CodingKeys: String, CodingKey {
        case fansRpm = "fans_rpm"
        case railsV = "rails_v"
        case systemC = "system_c"
        case vrmMosC = "vrm_mos_c"
        case pchC = "pch_c"
        case cpuSocketC = "cpu_socket_c"
    }
}

public struct HardwareInfo: Codable {
    public let ts: Double?
    public let gpus: [HardwareGPUInfo]?
    public let cpu: HardwareCPUInfo?
    public let cpuPackageW: Double?
    public let memory: HardwareMemoryInfo?
    public let board: HardwareBoardInfo?
    public let uptimeS: Double?
    public let powerProfile: String?
    public let unsupported: [String]?

    enum CodingKeys: String, CodingKey {
        case ts, gpus, cpu, memory, board, unsupported
        case cpuPackageW = "cpu_package_w"
        case uptimeS = "uptime_s"
        case powerProfile = "power_profile"
    }

    /// The card that actually runs the model. Falls back to the hottest GPU when role is missing.
    public var primaryGPU: HardwareGPUInfo? {
        let all = gpus ?? []
        return all.first { $0.role == "primary" } ?? all.max { ($0.tempC ?? 0) < ($1.tempC ?? 0) }
    }

    public var secondaryGPU: HardwareGPUInfo? {
        let all = gpus ?? []
        return all.first { $0.role == "secondary" }
            ?? (all.count > 1 ? all.min { ($0.tempC ?? 0) < ($1.tempC ?? 0) } : nil)
    }
}

public struct MessageMeta: Codable, Hashable {
    public let tps: Double?
    public let ttft: Double?
    public let elapsed: Double?
    public let thoughtS: Double?
    public let tokens: Int?
    public let promptTokens: Int?
    public let cachedTokens: Int?
    public let maxContext: Int?
    // Tokens this turn occupied (prompt + generated), from the backend. Nil on older messages.
    public let contextUsed: Int?
    public let variant: String?
    public let model: String?
    public let finishReason: String?
    public let tools: [ToolCall]?
    // Ordered reasoning/content blocks recorded by the backend when a turn interleaves them.
    public let segments: [MessageSegment]?
    
    enum CodingKeys: String, CodingKey {
        case tps, ttft, elapsed, tokens, variant, model, tools, segments
        case thoughtS = "thought_s"
        case promptTokens = "prompt_tokens"
        case cachedTokens = "cached_tokens"
        case maxContext = "max_context"
        case contextUsed = "context_used"
        case finishReason = "finish_reason"
    }
    
    public init(
        tps: Double? = nil,
        ttft: Double? = nil,
        elapsed: Double? = nil,
        thoughtS: Double? = nil,
        tokens: Int? = nil,
        promptTokens: Int? = nil,
        cachedTokens: Int? = nil,
        maxContext: Int? = 262144,
        contextUsed: Int? = nil,
        variant: String? = nil,
        model: String? = nil,
        finishReason: String? = nil,
        tools: [ToolCall]? = nil,
        segments: [MessageSegment]? = nil
    ) {
        self.tps = tps
        self.ttft = ttft
        self.elapsed = elapsed
        self.thoughtS = thoughtS
        self.tokens = tokens
        self.promptTokens = promptTokens
        self.cachedTokens = cachedTokens
        self.maxContext = maxContext
        self.contextUsed = contextUsed
        self.variant = variant
        self.model = model
        self.finishReason = finishReason
        self.tools = tools
        self.segments = segments
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tps = try? c.decodeIfPresent(Double.self, forKey: .tps)
        self.ttft = try? c.decodeIfPresent(Double.self, forKey: .ttft)
        self.elapsed = try? c.decodeIfPresent(Double.self, forKey: .elapsed)
        self.thoughtS = try? c.decodeIfPresent(Double.self, forKey: .thoughtS)
        self.tokens = try? c.decodeIfPresent(Int.self, forKey: .tokens)
        self.promptTokens = try? c.decodeIfPresent(Int.self, forKey: .promptTokens)
        self.cachedTokens = try? c.decodeIfPresent(Int.self, forKey: .cachedTokens)
        self.maxContext = (try? c.decodeIfPresent(Int.self, forKey: .maxContext)) ?? 262144
        self.variant = try? c.decodeIfPresent(String.self, forKey: .variant)
        self.model = try? c.decodeIfPresent(String.self, forKey: .model)
        self.finishReason = try? c.decodeIfPresent(String.self, forKey: .finishReason)
        self.tools = try? c.decodeIfPresent([ToolCall].self, forKey: .tools)
        self.contextUsed = try? c.decodeIfPresent(Int.self, forKey: .contextUsed)
        self.segments = try? c.decodeIfPresent([MessageSegment].self, forKey: .segments)
    }
}

public struct GeneratedFileInfo: Codable, Hashable, Identifiable {
    public var id: String { filename }
    public let filename: String
    public let title: String
    public let fileType: String // "pdf" or "docx"
    public let sizeBytes: Int64
    public let localPath: String
    
    public init(filename: String, title: String, fileType: String, sizeBytes: Int64, localPath: String) {
        self.filename = filename
        self.title = title
        self.fileType = fileType
        self.sizeBytes = sizeBytes
        self.localPath = localPath
    }
    
    public var sizeFormatted: String {
        let kb = Double(sizeBytes) / 1024.0
        if kb >= 1024.0 {
            return String(format: "%.1f MB", kb / 1024.0)
        }
        return String(format: "%.0f KB", max(1.0, kb))
    }
    
    public var fileTypeDisplay: String {
        switch fileType.lowercased() {
        case "pdf": return "PDF Document"
        case "docx", "word": return "Microsoft Word (.docx)"
        default: return fileType.uppercased()
        }
    }
    
    public var fileURL: URL {
        URL(fileURLWithPath: localPath)
    }
}

public struct ChatMessage: Codable, Identifiable, Hashable {
    public let id: String
    public let chatId: String
    public let role: String // "user" or "assistant"
    public var content: String
    public var status: String // "done", "streaming", "error"
    public var reasoning: String?
    public var thinkingMs: Int?
    public let images: [String]?
    public var jobId: String?
    public var error: String?
    public let created: Double?
    public var toolCalls: [ToolCall]?
    public var approvalPrompt: ApprovalPrompt?
    public var clarifyPrompt: ClarifyPrompt?
    public var meta: MessageMeta?
    public var phase: String? = nil
    // Live prefill progress (engine-reported; nil when the engine gave no stats)
    public var prefillRead: Int? = nil
    public var prefillTotal: Int? = nil
    public var prefillTokS: Double? = nil
    public var generatedFiles: [GeneratedFileInfo]? = nil
    
    enum CodingKeys: String, CodingKey {
        case id
        case chatId = "chat_id"
        case role, content, status, reasoning
        case thinkingMs = "thinking_ms"
        case images
        case jobId = "job_id"
        case error
        case created
        case toolCalls = "tool_calls"
        case approvalPrompt = "approval_prompt"
        case clarifyPrompt = "clarify_prompt"
        case meta
        case generatedFiles = "generated_files"
    }
    
    public var isUser: Bool { role == "user" }
    
    public var thinking: String? {
        get { reasoning }
        set { reasoning = newValue }
    }
    
    public var createdAt: Double {
        return created ?? Date().timeIntervalSince1970
    }
    
    public init(
        id: String,
        chatId: String,
        role: String,
        content: String,
        status: String = "done",
        thinking: String? = nil,
        thinkingMs: Int? = nil,
        images: [String]? = nil,
        jobId: String? = nil,
        error: String? = nil,
        createdAt: Double = Date().timeIntervalSince1970,
        toolCalls: [ToolCall]? = nil,
        approvalPrompt: ApprovalPrompt? = nil,
        clarifyPrompt: ClarifyPrompt? = nil,
        meta: MessageMeta? = nil,
        generatedFiles: [GeneratedFileInfo]? = nil
    ) {
        self.id = id
        self.chatId = chatId
        self.role = role
        self.content = content
        self.status = status
        self.reasoning = thinking
        self.thinkingMs = thinkingMs
        self.images = images
        self.jobId = jobId
        self.error = error
        self.created = createdAt
        self.toolCalls = toolCalls
        self.approvalPrompt = approvalPrompt
        self.clarifyPrompt = clarifyPrompt
        self.meta = meta
        self.generatedFiles = generatedFiles
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.chatId = (try? c.decode(String.self, forKey: .chatId)) ?? ""
        self.role = (try? c.decode(String.self, forKey: .role)) ?? "user"
        self.content = (try? c.decode(String.self, forKey: .content)) ?? ""
        self.status = (try? c.decode(String.self, forKey: .status)) ?? "done"
        self.reasoning = try? c.decodeIfPresent(String.self, forKey: .reasoning)
        self.thinkingMs = try? c.decodeIfPresent(Int.self, forKey: .thinkingMs)
        self.images = try? c.decodeIfPresent([String].self, forKey: .images)
        self.jobId = try? c.decodeIfPresent(String.self, forKey: .jobId)
        self.error = try? c.decodeIfPresent(String.self, forKey: .error)
        self.created = try? c.decodeIfPresent(Double.self, forKey: .created)
        self.meta = try? c.decodeIfPresent(MessageMeta.self, forKey: .meta)
        let decodedTools = try? c.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        self.toolCalls = (decodedTools != nil && !decodedTools!.isEmpty) ? decodedTools : self.meta?.tools
        self.approvalPrompt = try? c.decodeIfPresent(ApprovalPrompt.self, forKey: .approvalPrompt)
        self.clarifyPrompt = try? c.decodeIfPresent(ClarifyPrompt.self, forKey: .clarifyPrompt)
        self.generatedFiles = try? c.decodeIfPresent([GeneratedFileInfo].self, forKey: .generatedFiles)
    }
}

public struct HermesLockState: Codable, Hashable {
    public let model: String?
    public let effort: String?
    public let locked: Bool

    public init(model: String?, effort: String?, locked: Bool) {
        self.model = model
        self.effort = effort
        self.locked = locked
    }
}

public struct ChatDetail: Codable {
    public let id: String
    public var title: String
    public let backend: String
    public let created: Double?
    public let updated: Double?
    public var messages: [ChatMessage]
    // What Hermes has actually locked for this chat. Absent for a chat Hermes never locked - a chat
    // started in the desktop app sends no lock at all, so its effort is a runtime default, not a choice.
    public let hermesLock: HermesLockState?
    
    enum CodingKeys: String, CodingKey {
        case id, title, backend
        case created, updated
        case messages
        case hermesLock = "hermes_lock"
    }
    
    public var createdAt: Double { created ?? 0 }
    public var updatedAt: Double { updated ?? 0 }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = (try? c.decode(String.self, forKey: .title)) ?? "Chat"
        self.backend = (try? c.decode(String.self, forKey: .backend)) ?? "strata"
        self.created = try? c.decodeIfPresent(Double.self, forKey: .created)
        self.updated = try? c.decodeIfPresent(Double.self, forKey: .updated)
        self.messages = (try? c.decode([ChatMessage].self, forKey: .messages)) ?? []
        self.hermesLock = try? c.decodeIfPresent(HermesLockState.self, forKey: .hermesLock)
    }
}

public struct SendResponse: Codable {
    public let chat: ChatSummary
    public let userMessage: ChatMessage
    public let assistantMessage: ChatMessage
    public let jobId: String
    
    enum CodingKeys: String, CodingKey {
        case chat
        case userMessage = "user_message"
        case assistantMessage = "assistant_message"
        case jobId = "job_id"
    }
}

public struct RegenResponse: Codable {
    public let assistantMessage: ChatMessage
    public let jobId: String
    
    enum CodingKeys: String, CodingKey {
        case assistantMessage = "assistant_message"
        case jobId = "job_id"
    }
}

public struct EditResponse: Codable {
    public let chat: ChatDetail
    public let assistantMessage: ChatMessage
    public let jobId: String
    
    enum CodingKeys: String, CodingKey {
        case chat
        case assistantMessage = "assistant_message"
        case jobId = "job_id"
    }
}

public struct VoiceOption: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let gender: String?
    public let accent: String?
    public let tag: String?
    public let flagship: Bool?
    
    public init(id: String, name: String, gender: String? = nil, accent: String? = nil, tag: String? = nil, flagship: Bool? = nil) {
        self.id = id
        self.name = name
        self.gender = gender
        self.accent = accent
        self.tag = tag
        self.flagship = flagship
    }
}

public struct VoiceListResponse: Codable {
    public let voices: [VoiceOption]
    public let all: [String]
}

