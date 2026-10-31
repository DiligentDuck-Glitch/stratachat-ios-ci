import Foundation
import SwiftUI
import Combine

@MainActor
public class ChatViewModel: ObservableObject {
    @Published public var chats: [ChatSummary] = []
    @Published public var currentChatId: String? = nil
    @Published public var currentChatTitle: String = "Strata"
    @Published public var messages: [ChatMessage] = []
    @Published public var backend: Backend = {
        if let saved = UserDefaults.standard.string(forKey: "strata_last_active_backend"),
           let b = Backend(rawValue: saved) {
            return b
        }
        return .strata
    }() {
        didSet {
            UserDefaults.standard.set(backend.rawValue, forKey: "strata_last_active_backend")
            applyPreferredVariantForCurrentBackend()
        }
    }
    
    public func preferredVariant(for b: Backend) -> String {
        switch b {
        case .strata:
            return UserDefaults.standard.string(forKey: "strata_last_variant_strata") ?? "swift-160k"
        case .hermes:
            return UserDefaults.standard.string(forKey: "strata_last_variant_hermes") ?? "swift-160k"
        case .local:
            return ""
        }
    }
    
    public func setPreferredVariant(_ variant: String, for b: Backend) {
        switch b {
        case .strata:
            UserDefaults.standard.set(variant, forKey: "strata_last_variant_strata")
        case .hermes:
            UserDefaults.standard.set(variant, forKey: "strata_last_variant_hermes")
        case .local:
            break
        }
    }
    
    public func applyPreferredVariantForCurrentBackend() {
        guard backend != .local else { return }
        Task {
            // If the server already has ANY model loaded or active, adopt that active variant
            // instead of forcing a reload/restart of the engine!
            if let status = try? await client.getStatus() {
                if let currentVariant = status.variant, currentVariant != "unknown" {
                    // Save and adopt the current live variant
                    UserDefaults.standard.set(currentVariant, forKey: backend == .hermes ? "strata_last_variant_hermes" : "strata_last_variant_strata")
                    let limit: Int
                    switch currentVariant {
                    case "swift-64k": limit = 65536
                    case "swift-128k": limit = 131072
                    case "swift-160k", "original": limit = 163840
                    case "swift": limit = 262144
                    default: limit = 163840
                    }
                    self.configuredMaxContext = limit
                    UserDefaults.standard.set(limit, forKey: "strata_active_context_limit")
                    return
                }
            }
            
            let preferred = preferredVariant(for: backend)
            guard !preferred.isEmpty else { return }
            let limit: Int
            switch preferred {
            case "swift-64k": limit = 65536
            case "swift-128k": limit = 131072
            case "swift-160k", "original": limit = 163840
            case "swift": limit = 262144
            default: limit = 163840
            }
            self.configuredMaxContext = limit
            UserDefaults.standard.set(limit, forKey: "strata_active_context_limit")
            if let status = try? await client.getStatus(), status.variant == preferred { return }
            try? await client.switchVariant(variant: preferred)
        }
    }
    
    private var liveChatTask: Task<Void, Never>?
    
    /// An open chat gets no push when another client adds turns, so it re-reads itself while open.
    public func startLiveChatRefresh() {
        liveChatTask?.cancel()
        liveChatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard let self = self, !Task.isCancelled else { return }
                if self.isGenerating { continue }
                await self.refreshCurrentChat()
            }
        }
    }
    
    public func stopLiveChatRefresh() {
        liveChatTask?.cancel()
        liveChatTask = nil
    }
    @Published public var inputText: String = ""
    @Published public var attachedImages: [UIImage] = []
    @Published public var attachedClipData: Data? = nil
    @Published public var attachedClipContainer: String = "mp4"
    @Published public var attachedClipThumb: UIImage? = nil
    @Published public var queuedPrompts: [String] = []
    @Published public var isGenerating: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var showDrawer: Bool = false {
        didSet {
            if showDrawer {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }
    @Published public var drawerDragOffset: CGFloat = 0
    @Published public var isDraggingDrawer: Bool = false {
        didSet {
            if isDraggingDrawer {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }
    @Published public var showSettings: Bool = false
    @Published public var showModelPicker: Bool = false
    @Published public var showLocalModelManager: Bool = false
    @Published public var showContextSheet: Bool = false
    @Published public var showPerformanceSheet: Bool = false
    // The reply the Performance sheet was opened from. Nil when opened from the top-bar ring, and the
    // sheet then falls back to the newest reply that carries metrics.
    @Published public var performanceMessage: ChatMessage?
    // PC telemetry for the top-bar dual temperature ring and the Performance sheet. One poller, in the
    // view model: a Timer.publish held by a View struct is rebuilt on every re-render and never reaches
    // its fire date, which is exactly why the ring sat on "?" while the sheet's own loop worked. The
    // working status heartbeat is view-model polling too, so this follows the pattern that already lands.
    @Published public var pcHardware: HardwareInfo?
    @Published public var pcHardwareError: String?
    private var hardwareTask: Task<Void, Never>?
    private static let hardwarePollSeconds: Double = 1.0

    public func startHardwarePolling() {
        guard hardwareTask == nil else { return }
        hardwareTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshPCHardware()
                try? await Task.sleep(nanoseconds: UInt64(Self.hardwarePollSeconds * 1_000_000_000))
            }
        }
    }

    public func stopHardwarePolling() {
        hardwareTask?.cancel()
        hardwareTask = nil
    }

    // The sheet calls this so opening it forces a fresh reading instead of waiting up to a second.
    public func refreshPCHardwareNow() async {
        await refreshPCHardware()
    }

    private func refreshPCHardware() async {
        guard backend != .local else {
            pcHardware = nil
            pcHardwareError = nil
            return
        }
        do {
            pcHardware = try await APIClient.shared.getHardware()
            pcHardwareError = nil
        } catch {
            pcHardwareError = "No telemetry from the PC. Is it awake and paired?"
        }
    }
    @Published public var showVoiceMode: Bool = false
    @Published public var editingMessage: ChatMessage? = nil
    @Published public var isWakingPC: Bool = false
    @Published public var wakingStatus: String? = nil
    // Effort is per-chat. One global UserDefaults key meant every chat inherited whatever the last
    // chat happened to use, which is how a chat started on the PC appeared to carry an effort this
    // phone never chose. An override stored for a chat wins; otherwise the effort Hermes actually
    // recorded for that chat is used, and only then the global default.
    @Published public var hermesLock: HermesLockState?
    private static let effortOverridesKey = "strata_effort_by_chat"

    public func effortOverride(forChat chatId: String?) -> EffortLevel? {
        guard let chatId, !chatId.isEmpty else { return nil }
        let map = UserDefaults.standard.dictionary(forKey: Self.effortOverridesKey) as? [String: String]
        guard let raw = map?[chatId] else { return nil }
        return EffortLevel(rawValue: raw)
    }

    public func setEffortLevel(_ level: EffortLevel, forChat chatId: String?) {
        effortLevel = level
        guard let chatId, !chatId.isEmpty else { return }
        var map = UserDefaults.standard.dictionary(forKey: Self.effortOverridesKey) as? [String: String] ?? [:]
        map[chatId] = level.rawValue
        UserDefaults.standard.set(map, forKey: Self.effortOverridesKey)
    }

    // Hermes spellings that the app's five chips do not have names for.
    private static func normalizeEffort(_ raw: String) -> EffortLevel? {
        switch raw {
        case "none": return .off
        case "minimal": return .low
        case "xhigh", "ultra": return .max
        default: return EffortLevel(rawValue: raw)
        }
    }

    // Called on every chat load, so opening a chat that another device started shows that chat's
    // real recorded effort instead of this phone's last-used setting.
    public func applyServerEffort(_ detail: ChatDetail) {
        hermesLock = detail.hermesLock
        if let override = effortOverride(forChat: detail.id) {
            effortLevel = override
            return
        }
        if let recorded = detail.hermesLock?.effort, let level = Self.normalizeEffort(recorded) {
            effortLevel = level
        }
    }

    @Published public var effortLevel: EffortLevel = EffortLevel(rawValue: UserDefaults.standard.string(forKey: "strata_effort_level") ?? "medium") ?? .medium {
        didSet {
            UserDefaults.standard.set(effortLevel.rawValue, forKey: "strata_effort_level")
        }
    }
    
    private let client = APIClient.shared
    private var streamTask: Task<Void, Never>? = nil
    private var activeJobId: String? = nil
    private var activeBgTaskId: UIBackgroundTaskIdentifier = .invalid
    private var foregroundObserver: NSObjectProtocol? = nil
    private var backgroundObserver: NSObjectProtocol? = nil
    private var localEngineCancellable: AnyCancellable? = nil
    private var contentPacer: StreamPacer? = nil
    private var thinkingPacer: StreamPacer? = nil
    
    deinit {
        if let fo = foregroundObserver { NotificationCenter.default.removeObserver(fo) }
        if let bo = backgroundObserver { NotificationCenter.default.removeObserver(bo) }
        if activeBgTaskId != .invalid {
            BackgroundTaskManager.shared.endTask(activeBgTaskId)
        }
    }
    
    public var currentContextTokens: Int {
        if backend == .local {
            if messages.isEmpty {
                return 0
            }
            let liveUsed = LocalInferenceEngine.shared.activeContextUsedTokens
            if liveUsed > 0 {
                return min(maxContextTokens, liveUsed)
            }
            if let lastMeta = messages.reversed().first(where: { $0.role == "assistant" && $0.meta != nil })?.meta {
                let prompt = lastMeta.promptTokens ?? 0
                let out = lastMeta.tokens ?? 0
                if prompt + out > 0 {
                    return min(maxContextTokens, prompt + out)
                }
            }
            let totalChars = messages.reduce(0) { $0 + $1.content.count + ($1.reasoning?.count ?? 0) }
            return min(maxContextTokens, max(0, Int(Double(totalChars) / 3.5)))
        }
        if let lastMeta = messages.reversed().first(where: { $0.role == "assistant" && $0.meta != nil })?.meta {
            let prompt = lastMeta.promptTokens ?? 0
            let out = lastMeta.tokens ?? 0
            if prompt + out > 0 {
                return min(maxContextTokens, prompt + out)
            }
        }
        // Fallback estimate based on recent turns within the active window
        let recent = messages.suffix(30)
        let totalChars = recent.reduce(0) { $0 + $1.content.count + ($1.reasoning?.count ?? 0) }
        return min(maxContextTokens, max(0, Int(Double(totalChars) / 3.6)))
    }
    
    @Published public var configuredMaxContext: Int = {
        let saved = UserDefaults.standard.integer(forKey: "strata_active_context_limit")
        return saved > 0 ? saved : 262144
    }()
    
    public var maxContextTokens: Int {
        if backend == .local {
            return LocalInferenceEngine.shared.contextLength
        }
        if configuredMaxContext > 0 {
            return configuredMaxContext
        }
        if let lastMeta = messages.reversed().first(where: { $0.meta?.maxContext != nil })?.meta,
           let maxC = lastMeta.maxContext, maxC > 0 {
            return maxC
        }
        return 262144
    }
    
    public var contextRatio: Double {
        guard maxContextTokens > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(currentContextTokens) / Double(maxContextTokens)))
    }
    
    public var cachedTokens: Int {
        if backend == .local {
            let liveCached = LocalInferenceEngine.shared.activeContextCachedTokens
            if liveCached > 0 { return liveCached }
        }
        return messages.reversed().first(where: { $0.meta?.cachedTokens != nil })?.meta?.cachedTokens ?? 0
    }
    
    public init() {
        self.localEngineCancellable = LocalInferenceEngine.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        
        self.foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWillEnterForeground()
        }
        
        self.backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidEnterBackground()
        }
        
        Task {
            await loadChats()
            let savedChatId = UserDefaults.standard.string(forKey: "strata_last_active_chat_id")
            if let sId = savedChatId, chats.contains(where: { $0.id == sId }) {
                selectChat(id: sId)
            } else {
                let targetBackend = backend
                let matchingChats = chats.filter {
                    if targetBackend == .local { return $0.backend == "local" }
                    else if targetBackend == .hermes { return $0.backend == "hermes" }
                    else { return $0.backend != "hermes" && $0.backend != "local" }
                }
                if let firstMatching = matchingChats.first {
                    selectChat(id: firstMatching.id)
                } else if currentChatId == nil {
                    newChat(backend: targetBackend)
                }
            }
        }
    }
    
    private func handleDidEnterBackground() {
        if (self.isGenerating || self.activeJobId != nil) && self.activeBgTaskId == .invalid {
            let name = "StrataJobStream-\(self.activeJobId ?? "active")"
            self.activeBgTaskId = BackgroundTaskManager.shared.beginTask(name: name)
        }
    }
    
    private func handleWillEnterForeground() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // If generating or waiting on a job, check server state to see if it finished while asleep
            if self.isGenerating || self.activeJobId != nil {
                if let cId = self.currentChatId {
                    if let detail = try? await self.client.getChat(id: cId),
                       let lastAssistant = detail.messages.last(where: { $0.role == "assistant" }) {
                        if lastAssistant.status == "done" || (!lastAssistant.content.isEmpty && (self.streamTask == nil || self.streamTask?.isCancelled == true)) {
                            // Completed on server while the device was suspended/backgrounded
                            self.messages = detail.messages
                            self.isGenerating = false
                            self.activeJobId = nil
                            self.contentPacer?.flushAll()
                            self.thinkingPacer?.flushAll()
                            if self.activeBgTaskId != .invalid {
                                BackgroundTaskManager.shared.endTask(self.activeBgTaskId)
                                self.activeBgTaskId = .invalid
                            }
                        } else if lastAssistant.status == "running" || self.isGenerating {
                            // Still running on server; ensure the stream connection is alive
                            if self.streamTask == nil || self.streamTask?.isCancelled == true {
                                if let jId = self.activeJobId {
                                    self.attachToStream(jobId: jId, assistantMessageId: lastAssistant.id)
                                }
                            }
                        }
                    }
                }
            }
            
            // Refresh hardware telemetry and chat list
            await self.refreshPCHardware()
            await self.loadChats()
        }
    }
    
    public func loadChats() async {
        await client.ensureAuthenticated()
        let localChats = LocalInferenceEngine.shared.loadLocalChats()
        do {
            let serverChats = try await client.listChats()
            var merged = localChats
            for sc in serverChats {
                if !merged.contains(where: { $0.id == sc.id }) {
                    merged.append(sc)
                }
            }
            self.chats = merged
        } catch {
            print("Failed to load server chats: \(error). Using local on-device chats.")
            self.chats = localChats
        }
    }
    
    /// Refetch the chat that is already open. Turns typed on the PC live in Hermes and nothing
    /// pushes them into an open transcript, so this is what makes "the phone stopped updating"
    /// fixable without closing the app. It refuses to run mid-stream so it cannot clobber a reply
    /// that is arriving right now.
    public func refreshCurrentChat() async {
        guard let id = currentChatId, !id.isEmpty else { return }
        guard !messages.contains(where: { $0.status == "streaming" }) else { return }
        await client.ensureAuthenticated()
        do {
            let detail = try await client.getChat(id: id)
            self.messages = detail.messages
            self.currentChatTitle = detail.title
            applyServerEffort(detail)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func selectChat(id: String, title: String? = nil, backend: String? = nil) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        UserDefaults.standard.set(id, forKey: "strata_last_active_chat_id")
        
        // Instant visual feedback: dismiss drawer and update titles immediately (0ms delay)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            self.showDrawer = false
            self.drawerDragOffset = 0
            self.isDraggingDrawer = false
            self.currentChatId = id
            if let t = title, !t.isEmpty {
                self.currentChatTitle = t
            }
            if let b = backend, let resolved = Backend(rawValue: b) {
                self.backend = resolved
                UserDefaults.standard.set(resolved.rawValue, forKey: "strata_last_active_backend")
            }
        }
        
        // If this is a local on-device chat, load from local storage directly (100% offline)
        if id.hasPrefix("local_") || backend == "local" {
            self.backend = .local
            UserDefaults.standard.set(Backend.local.rawValue, forKey: "strata_last_active_backend")
            self.messages = LocalInferenceEngine.shared.loadLocalMessages(chatId: id)
            if let lastMeta = self.messages.reversed().first(where: { $0.role == "assistant" && $0.meta != nil })?.meta {
                LocalInferenceEngine.shared.activeContextUsedTokens = (lastMeta.promptTokens ?? 0) + (lastMeta.tokens ?? 0)
                LocalInferenceEngine.shared.activeContextCachedTokens = lastMeta.cachedTokens ?? 0
            } else {
                LocalInferenceEngine.shared.activeContextUsedTokens = 0
                LocalInferenceEngine.shared.activeContextCachedTokens = 0
            }
            return
        }
        
        Task {
            await client.ensureAuthenticated()
            do {
                let detail = try await client.getChat(id: id)
                self.currentChatId = detail.id
                self.currentChatTitle = detail.title
                let resolved = Backend(rawValue: detail.backend) ?? .strata
                self.backend = resolved
                UserDefaults.standard.set(detail.id, forKey: "strata_last_active_chat_id")
                UserDefaults.standard.set(resolved.rawValue, forKey: "strata_last_active_backend")
                self.messages = detail.messages
                applyServerEffort(detail)
                
                // Check if last message was left streaming
                if let last = detail.messages.last, last.status == "streaming", let jId = last.jobId {
                    attachToStream(jobId: jId, assistantMessageId: last.id)
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    public func newChat(backend: Backend? = nil) {
        self.stop()
        if let b = backend {
            self.backend = b
        }
        self.currentChatId = nil
        UserDefaults.standard.removeObject(forKey: "strata_last_active_chat_id")
        UserDefaults.standard.set(self.backend.rawValue, forKey: "strata_last_active_backend")
        self.currentChatTitle = self.backend == .local ? "On-Device" : (self.backend == .hermes ? "Hermes Agent" : "Strata")
        self.messages = []
        self.inputText = ""
        self.attachedImages = []
        self.showDrawer = false
        if self.backend == .local {
            LocalInferenceEngine.shared.resetLocalSessionContext()
        }
        applyPreferredVariantForCurrentBackend()
    }
    
    public func startEditing(message: ChatMessage) {
        guard message.isUser else { return }
        self.editingMessage = message
        self.inputText = message.content
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    public func cancelEditing() {
        self.editingMessage = nil
        self.inputText = ""
    }
    
    public func submitEdit() {
        guard let editMsg = editingMessage, let chatId = currentChatId else {
            self.editingMessage = nil
            send()
            return
        }
        let newContent = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newContent.isEmpty else { return }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        self.inputText = ""
        self.editingMessage = nil
        self.isGenerating = true
        
        Task {
            do {
                let res = try await client.editMessage(
                    chatId: chatId,
                    messageId: editMsg.id,
                    content: newContent,
                    backend: self.backend,
                    effort: self.effortLevel
                )
                self.messages = res.chat.messages
                self.attachToStream(jobId: res.jobId, assistantMessageId: res.assistantMessage.id)
                await self.loadChats()
            } catch {
                self.errorMessage = error.localizedDescription
                self.isGenerating = false
            }
        }
    }
    
    public func undo() {
        guard let chatId = currentChatId, !isGenerating else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do {
                let detail = try await client.undo(chatId: chatId)
                self.messages = detail.messages
                await self.loadChats()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    public func compactChat() {
        guard let chatId = currentChatId, !isGenerating else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do {
                let detail = try await client.compactChat(chatId: chatId)
                self.messages = detail.messages
                await self.loadChats()
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    public func send(text: String? = nil) {
        if editingMessage != nil {
            submitEdit()
            return
        }
        
        let content = (text ?? inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        let imagesToUpload = attachedImages
        let clipData = attachedClipData
        let clipContainer = attachedClipContainer
        guard !content.isEmpty || !imagesToUpload.isEmpty || clipData != nil else { return }
        
        // Slash command interception
        if content.starts(with: "/") {
            let cmd = content.lowercased().trimmingCharacters(in: .whitespaces)
            if cmd == "/compact" {
                self.inputText = ""
                self.compactChat()
                return
            } else if cmd == "/undo" {
                self.inputText = ""
                self.undo()
                return
            } else if cmd == "/retry" || cmd == "/regen" {
                self.inputText = ""
                self.regenerate()
                return
            } else if cmd == "/clear" || cmd == "/reset" {
                self.inputText = ""
                self.newChat()
                return
            } else if cmd == "/model" {
                self.inputText = ""
                self.showModelPicker = true
                return
            } else if cmd == "/status" {
                self.inputText = ""
                self.showSettings = true
                return
            }
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        let base64Images: [String] = imagesToUpload.compactMap { img in
            guard let data = img.jpegData(compressionQuality: 0.8) else { return nil }
            return "data:image/jpeg;base64," + data.base64EncodedString()
        }
        
        self.inputText = ""
        self.attachedImages = []
        self.attachedClipData = nil
        self.attachedClipThumb = nil
        self.attachedClipContainer = "mp4"
        DispatchQueue.main.async {
            self.inputText = ""
        }
        self.isGenerating = true
        
        if self.backend == .local {
            if clipData != nil {
                self.errorMessage = "Video is read by Hermes or Strata, not the on-device model."
            }
            sendLocalTurn(content: content, images: base64Images)
            return
        }
        
        // Optimistic user message
        let tempUserMsg = ChatMessage(
            id: UUID().uuidString,
            chatId: currentChatId ?? "",
            role: "user",
            content: content,
            status: "done",
            thinking: nil,
            thinkingMs: nil,
            images: base64Images.isEmpty ? nil : base64Images,
            jobId: nil,
            error: nil,
            createdAt: Date().timeIntervalSince1970,
            toolCalls: nil,
            approvalPrompt: nil,
            clarifyPrompt: nil
        )
        self.messages.append(tempUserMsg)
        
        Task {
            do {
                // The clip travels first, so the send call can reference the frames the server sampled.
                var mediaIds: [String] = []
                if let clip = clipData {
                    let manifest = try await client.uploadVideo(data: clip, container: clipContainer)
                    if let mediaId = manifest["id"] as? String {
                        mediaIds.append(mediaId)
                    }
                }
                let res = try await client.send(
                    chatId: self.currentChatId,
                    content: content,
                    images: base64Images,
                    backend: self.backend,
                    effort: self.effortLevel,
                    mediaIds: mediaIds
                )
                
                self.currentChatId = res.chat.id
                UserDefaults.standard.set(res.chat.id, forKey: "strata_last_active_chat_id")
                self.currentChatTitle = res.chat.title
                
                // Replace optimistic user message with confirmed one, append assistant placeholder
                if let idx = self.messages.firstIndex(where: { $0.id == tempUserMsg.id }) {
                    self.messages[idx] = res.userMessage
                }
                self.messages.append(res.assistantMessage)
                
                self.attachToStream(jobId: res.jobId, assistantMessageId: res.assistantMessage.id)
                await self.loadChats()
            } catch {
                if self.isConnectionIssue(error) {
                    await self.attemptWakeAndRetry(content: content, base64Images: base64Images, tempUserMsgId: tempUserMsg.id)
                } else if let apiErr = error as? APIError, case .conflict(let jobId, let assistantMsgId) = apiErr {
                    if let jId = jobId {
                        self.activeJobId = jId
                        self.isGenerating = true
                        self.attachToStream(jobId: jId, assistantMessageId: assistantMsgId ?? "")
                        await self.loadChats()
                    } else {
                        self.isGenerating = false
                        self.errorMessage = "This chat is still generating."
                    }
                } else {
                    self.isGenerating = false
                    self.errorMessage = error.localizedDescription
                    if let idx = self.messages.firstIndex(where: { $0.id == tempUserMsg.id }) {
                        self.messages.remove(at: idx)
                        if self.inputText.isEmpty {
                            self.inputText = content
                        }
                    }
                }
            }
        }
    }
    
    private func sendLocalTurn(content: String, images: [String]) {
        let chatId = self.currentChatId ?? "local_\(UUID().uuidString)"
        self.currentChatId = chatId
        UserDefaults.standard.set(chatId, forKey: "strata_last_active_chat_id")
        UserDefaults.standard.set(Backend.local.rawValue, forKey: "strata_last_active_backend")
        if self.currentChatTitle == "Strata" || self.currentChatTitle == "Hermes Agent" || self.currentChatTitle == "On-Device" {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                self.currentChatTitle = String(trimmed.prefix(28))
            } else if !images.isEmpty {
                self.currentChatTitle = "Image Analysis"
            } else {
                self.currentChatTitle = "On-Device Chat"
            }
        }
        
        let userMsg = ChatMessage(
            id: UUID().uuidString,
            chatId: chatId,
            role: "user",
            content: content,
            status: "done",
            thinking: nil,
            thinkingMs: nil,
            images: images.isEmpty ? nil : images,
            jobId: nil,
            error: nil,
            createdAt: Date().timeIntervalSince1970,
            toolCalls: nil,
            approvalPrompt: nil,
            clarifyPrompt: nil
        )
        self.messages.append(userMsg)
        
        let assistantMsgId = UUID().uuidString
        let assistantMsg = ChatMessage(
            id: assistantMsgId,
            chatId: chatId,
            role: "assistant",
            content: "",
            status: "generating",
            thinking: nil,
            thinkingMs: nil,
            images: nil,
            jobId: nil,
            error: nil,
            createdAt: Date().timeIntervalSince1970,
            toolCalls: nil,
            approvalPrompt: nil,
            clarifyPrompt: nil
        )
        self.messages.append(assistantMsg)
        
        Task {
            do {
                // If user sent only an image with no text, provide default description instruction
                var promptWithTools = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if promptWithTools.isEmpty && !images.isEmpty {
                    promptWithTools = "Describe this image."
                }
                let lowerContent = promptWithTools.lowercased()
                if lowerContent.contains("pdf") || lowerContent.contains("word") || lowerContent.contains("docx") || lowerContent.contains("search") {
                    promptWithTools = LocalToolEngine.shared.toolInstructions + "\n\nUser: " + promptWithTools + "\n\nAssistant:"
                }
                
                let meta = try await LocalInferenceEngine.shared.generateStream(sessionId: chatId, prompt: promptWithTools, images: images) { [weak self] token in
                    guard let self = self else { return }
                    if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        self.messages[idx].content += token
                    }
                }
                
                if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                    var fullContent = self.messages[idx].content
                    
                    // Parse and execute any tool calls emitted by the model
                    let toolCalls = LocalToolEngine.shared.parseToolCalls(from: fullContent)
                    if !toolCalls.isEmpty {
                        for call in toolCalls {
                            let (resultText, generatedFile) = await LocalToolEngine.shared.executeTool(call)
                            fullContent = fullContent.replacingOccurrences(of: call.rawCallString, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            if let file = generatedFile {
                                var files = self.messages[idx].generatedFiles ?? []
                                files.append(file)
                                self.messages[idx].generatedFiles = files
                            }
                        }
                        if fullContent.isEmpty {
                            fullContent = "I've created the requested document for you. You can preview or share it below."
                        }
                        self.messages[idx].content = fullContent
                    } else if (lowerContent.contains("pdf")) && (lowerContent.contains("make") || lowerContent.contains("create")) {
                        // Direct safety net if model generated markdown without tool tags
                        let filename = "Document.pdf"
                        if let file = try? DocumentGenerator.shared.createPDF(filename: filename, title: "Document", markdown: fullContent) {
                            self.messages[idx].generatedFiles = [file]
                        }
                    } else if (lowerContent.contains("word") || lowerContent.contains("docx")) && (lowerContent.contains("make") || lowerContent.contains("create")) {
                        let filename = "Document.docx"
                        if let file = try? DocumentGenerator.shared.createWordDoc(filename: filename, title: "Document", markdown: fullContent) {
                            self.messages[idx].generatedFiles = [file]
                        }
                    }
                    
                    self.messages[idx].status = "done"
                    self.messages[idx].meta = meta
                }
                self.isGenerating = false
                
                let summary = ChatSummary(
                    id: chatId,
                    title: self.currentChatTitle,
                    backend: "local",
                    hermesSessionId: nil,
                    created: Date().timeIntervalSince1970,
                    updated: Date().timeIntervalSince1970,
                    preview: String(content.prefix(50)),
                    messageCount: self.messages.count
                )
                LocalInferenceEngine.shared.saveLocalChat(summary: summary, messages: self.messages)
                await self.loadChats()
            } catch {
                if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                    self.messages[idx].status = "error"
                    self.messages[idx].error = error.localizedDescription
                }
                self.isGenerating = false
            }
        }
    }
    
    private func isConnectionIssue(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .cannotConnectToHost ||
                   urlError.code == .cannotFindHost ||
                   urlError.code == .dnsLookupFailed
        }
        return false
    }
    
    private func attemptWakeAndRetry(content: String, base64Images: [String], tempUserMsgId: String) async {
        // Quick pre-check: if PC status can be fetched, it's not actually asleep
        var wokeUp = false
        if (try? await client.getStatus()) != nil {
            wokeUp = true
        } else {
            self.isWakingPC = true
            self.wakingStatus = "⚡ Broadcasting Wake-on-LAN... Waiting for PC to boot..."
            WakeOnLAN.sendMagicPacket()
            
            for attempt in 1...18 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if attempt % 3 == 0 {
                    WakeOnLAN.sendMagicPacket()
                }
                self.wakingStatus = "⚡ PC waking up... Connecting to Strata (\(attempt * 2)s)..."
                do {
                    _ = try await client.getStatus()
                    wokeUp = true
                    break
                } catch {
                    // still offline
                }
            }
        }
        
        if wokeUp {
            self.wakingStatus = "⚡ PC online! Sending prompt to Strata..."
            do {
                let res = try await client.send(
                    chatId: self.currentChatId,
                    content: content,
                    images: base64Images,
                    backend: self.backend,
                    effort: self.effortLevel
                )
                self.currentChatId = res.chat.id
                self.currentChatTitle = res.chat.title
                if let idx = self.messages.firstIndex(where: { $0.id == tempUserMsgId }) {
                    self.messages[idx] = res.userMessage
                }
                self.messages.append(res.assistantMessage)
                self.attachToStream(jobId: res.jobId, assistantMessageId: res.assistantMessage.id)
                await self.loadChats()
                self.isWakingPC = false
                self.wakingStatus = nil
                return
            } catch {
                if let apiErr = error as? APIError, case .conflict(let jobId, let assistantMsgId) = apiErr, let jId = jobId {
                    self.activeJobId = jId
                    self.isGenerating = true
                    self.attachToStream(jobId: jId, assistantMessageId: assistantMsgId ?? "")
                    await self.loadChats()
                    self.isWakingPC = false
                    self.wakingStatus = nil
                    return
                }
                self.errorMessage = "Message failed: \(error.localizedDescription)"
            }
        } else {
            self.errorMessage = "Could not wake PC. If on mobile data, connect to home Wi-Fi for Wake-on-LAN."
        }
        
        self.isWakingPC = false
        self.wakingStatus = nil
        self.isGenerating = false
        if let idx = self.messages.firstIndex(where: { $0.id == tempUserMsgId }) {
            self.messages.remove(at: idx)
        }
    }
    
    public func regenerate() {
        guard let chatId = currentChatId, !isGenerating else { return }
        self.isGenerating = true
        
        Task {
            do {
                let res = try await client.regenerate(chatId: chatId, backend: self.backend, effort: self.effortLevel)
                // Remove previous assistant message if needed
                if self.messages.last?.role == "assistant" {
                    self.messages.removeLast()
                }
                self.messages.append(res.assistantMessage)
                self.attachToStream(jobId: res.jobId, assistantMessageId: res.assistantMessage.id)
            } catch {
                if let apiErr = error as? APIError, case .conflict(let jobId, let assistantMsgId) = apiErr, let jId = jobId {
                    self.activeJobId = jId
                    self.isGenerating = true
                    self.attachToStream(jobId: jId, assistantMessageId: assistantMsgId ?? "")
                    return
                }
                self.isGenerating = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    public func enqueuePrompt() {
        let draft = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }
        queuedPrompts.append(draft)
        inputText = ""
    }

    public func clearQueue() {
        queuedPrompts.removeAll()
    }

    /// Sends the next queued prompt once the running reply has ended.
    public func drainQueue() {
        guard !isGenerating, !queuedPrompts.isEmpty else { return }
        let next = queuedPrompts.removeFirst()
        send(text: next)
    }

    public func stop() {
        if let jId = activeJobId {
            Task {
                await client.cancelJob(jobId: jId)
            }
        }
        if let cId = currentChatId {
            Task {
                await client.stopChat(chatId: cId)
            }
        }
        streamTask?.cancel()
        streamTask = nil
        contentPacer?.flushAll()
        contentPacer = nil
        thinkingPacer?.flushAll()
        thinkingPacer = nil
        activeJobId = nil
        isGenerating = false
        if activeBgTaskId != .invalid {
            BackgroundTaskManager.shared.endTask(activeBgTaskId)
            activeBgTaskId = .invalid
        }
        
        // Immediately halt animation and mark message cancelled in local UI
        if let lastIdx = messages.indices.last, messages[lastIdx].role == "assistant" && (messages[lastIdx].status == "streaming" || messages[lastIdx].status == "generating") {
            messages[lastIdx].status = "cancelled"
            messages[lastIdx].phase = nil
        }
    }
    
    public func renameChat(id: String, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            if let idx = self.chats.firstIndex(where: { $0.id == id }) {
                self.chats[idx].title = trimmed
            }
            if self.currentChatId == id {
                self.currentChatTitle = trimmed
            }
        }
        
        if id.hasPrefix("local_") {
            LocalInferenceEngine.shared.renameLocalChat(id: id, newTitle: trimmed)
            return
        }
        
        Task {
            do {
                try await client.renameChat(id: id, title: trimmed)
            } catch {
                self.errorMessage = error.localizedDescription
                await loadChats()
            }
        }
    }
    
    public func deleteChat(id: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let backupChats = self.chats
        let wasActive = (self.currentChatId == id)
        
        // Optimistic instant UI update (0ms latency, zero lag!)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            self.chats.removeAll { $0.id == id }
            if wasActive {
                self.newChat()
            }
        }
        
        if id.hasPrefix("local_") {
            LocalInferenceEngine.shared.deleteLocalChat(id: id)
            return
        }
        
        Task {
            do {
                try await client.deleteChat(id: id)
            } catch {
                await MainActor.run {
                    withAnimation {
                        self.chats = backupChats
                    }
                    self.errorMessage = "Failed to delete chat: \(error.localizedDescription)"
                }
            }
        }
    }
    
    public func respondApproval(promptId: String, choice: String) {
        let jId = activeJobId ?? messages.last(where: { $0.approvalPrompt?.id == promptId })?.jobId
        guard let jId else {
            self.errorMessage = "Can't send approval: this request is no longer active."
            return
        }
        Task {
            do {
                try await client.submitApproval(jobId: jId, promptId: promptId, choice: choice)
                if let idx = self.messages.firstIndex(where: { $0.approvalPrompt?.id == promptId }) {
                    self.messages[idx].approvalPrompt?.resolved = choice
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    public func respondClarify(promptId: String, answer: String) {
        let jId = activeJobId ?? messages.last(where: { $0.clarifyPrompt?.id == promptId })?.jobId
        guard let jId else {
            self.errorMessage = "Can't send answer: this request is no longer active."
            return
        }
        Task {
            do {
                try await client.submitClarify(jobId: jId, promptId: promptId, answer: answer)
                if let idx = self.messages.firstIndex(where: { $0.clarifyPrompt?.id == promptId }) {
                    self.messages[idx].clarifyPrompt?.resolved = answer
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    private func attachToStream(jobId: String, assistantMessageId: String) {
        self.streamTask?.cancel()
        self.contentPacer?.stop()
        self.contentPacer = nil
        self.thinkingPacer?.stop()
        self.thinkingPacer = nil
        self.activeJobId = jobId
        self.isGenerating = true
        
        if self.activeBgTaskId != .invalid {
            BackgroundTaskManager.shared.endTask(self.activeBgTaskId)
            self.activeBgTaskId = .invalid
        }
        self.activeBgTaskId = BackgroundTaskManager.shared.beginTask(name: "StrataJobStream-\(jobId)")
        
        var streamFirstTokenTime: Date? = nil
        var streamTokenChars: Int = 0
        
        let cPacer = StreamPacer { [weak self] chunk in
            guard let self = self else { return }
            var idx = self.messages.firstIndex(where: { $0.id == assistantMessageId })
            if idx == nil {
                idx = self.messages.firstIndex(where: { $0.jobId == jobId })
            }
            if idx == nil, let lastIdx = self.messages.indices.last, self.messages[lastIdx].role == "assistant" {
                idx = lastIdx
            }
            guard let targetIdx = idx else { return }
            if self.messages[targetIdx].content.isEmpty {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            self.messages[targetIdx].content += chunk
        }
        self.contentPacer = cPacer
        
        let tPacer = StreamPacer { [weak self] chunk in
            guard let self = self else { return }
            var idx = self.messages.firstIndex(where: { $0.id == assistantMessageId })
            if idx == nil {
                idx = self.messages.firstIndex(where: { $0.jobId == jobId })
            }
            if idx == nil, let lastIdx = self.messages.indices.last, self.messages[lastIdx].role == "assistant" {
                idx = lastIdx
            }
            guard let targetIdx = idx else { return }
            if self.messages[targetIdx].thinking == nil {
                self.messages[targetIdx].thinking = chunk
            } else {
                self.messages[targetIdx].thinking! += chunk
            }
        }
        self.thinkingPacer = tPacer
        
        self.streamTask = client.streamJob(jobId: jobId) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                var idx = self.messages.firstIndex(where: { $0.id == assistantMessageId })
                if idx == nil {
                    idx = self.messages.firstIndex(where: { $0.jobId == jobId })
                }
                if idx == nil, let lastIdx = self.messages.indices.last, self.messages[lastIdx].role == "assistant" {
                    idx = lastIdx
                }
                guard let targetIdx = idx else { return }
                
                switch event.payload {
                case .phase(let ph):
                    if ph == "loading" {
                        self.messages[targetIdx].phase = "Waking RTX 5070 Ti (loading 16GB VRAM)..."
                    } else if ph == "prefill" {
                        self.messages[targetIdx].phase = "Prefilling"
                    } else if ph == "thinking" {
                        self.messages[targetIdx].phase = "Reasoning..."
                        self.messages[targetIdx].prefillRead = nil
                        self.messages[targetIdx].prefillTotal = nil
                        self.messages[targetIdx].prefillTokS = nil
                    } else if ph == "answering" {
                        self.messages[targetIdx].phase = "Generating response..."
                    } else {
                        self.messages[targetIdx].phase = "Prefilling"
                    }
                case .prefill(let read, let total, let tokS):
                    self.messages[targetIdx].prefillRead = read
                    self.messages[targetIdx].prefillTotal = total
                    self.messages[targetIdx].prefillTokS = tokS
                    self.messages[targetIdx].phase = "Prefilling"
                case .content(let text):
                    self.messages[targetIdx].phase = nil
                    self.messages[targetIdx].prefillRead = nil
                    self.messages[targetIdx].prefillTotal = nil
                    self.messages[targetIdx].prefillTokS = nil
                    self.thinkingPacer?.flushAll()
                    self.contentPacer?.feed(text)
                    
                    if streamFirstTokenTime == nil {
                        streamFirstTokenTime = Date()
                    }
                    streamTokenChars += text.count
                    let estTokens = max(1, Int(Double(streamTokenChars) / 3.6))
                    let elapsed = max(0.2, Date().timeIntervalSince(streamFirstTokenTime!))
                    let liveTps = Double(estTokens) / elapsed
                    
                    let prev = self.messages[targetIdx].meta
                    self.messages[targetIdx].meta = MessageMeta(
                        tps: liveTps,
                        ttft: prev?.ttft,
                        elapsed: elapsed,
                        thoughtS: prev?.thoughtS,
                        tokens: estTokens,
                        promptTokens: prev?.promptTokens,
                        cachedTokens: prev?.cachedTokens,
                        maxContext: prev?.maxContext ?? 262144,
                        variant: prev?.variant,
                        model: prev?.model ?? "Hermes Agent",
                        finishReason: prev?.finishReason,
                        tools: self.messages[targetIdx].toolCalls
                    )
                case .reasoning(let text):
                    self.thinkingPacer?.feed(text)
                    if streamFirstTokenTime == nil {
                        streamFirstTokenTime = Date()
                    }
                    streamTokenChars += text.count
                case .toolProgress(let toolId, let tool, let status):
                    var tools = self.messages[targetIdx].toolCalls ?? []
                    if let tIdx = tools.firstIndex(where: { $0.id == toolId }) {
                        tools[tIdx].status = status
                    } else if let tIdx = tools.lastIndex(where: { $0.name == tool && $0.status == "running" }) {
                        tools[tIdx].status = status
                    } else {
                        tools.append(ToolCall(id: toolId, name: tool, status: status))
                    }
                    self.messages[targetIdx].toolCalls = tools
                case .approvalPrompt(let id, let cmd, let reason):
                    self.messages[targetIdx].approvalPrompt = ApprovalPrompt(id: id, command: cmd, reason: reason, resolved: nil)
                    NotificationManager.shared.notifyApprovalPrompt(id: id, command: cmd, reason: reason)
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                case .clarifyPrompt(let id, let q, let choices):
                    self.messages[targetIdx].clarifyPrompt = ClarifyPrompt(id: id, question: q, choices: choices, resolved: nil)
                    NotificationManager.shared.notifyClarifyPrompt(id: id, question: q)
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                case .controlSettled(let id, let res):
                    if let pIdx = self.messages.firstIndex(where: { $0.approvalPrompt?.id == id }) {
                        self.messages[pIdx].approvalPrompt?.resolved = res ?? "settled"
                    }
                    if let cIdx = self.messages.firstIndex(where: { $0.clarifyPrompt?.id == id }) {
                        self.messages[cIdx].clarifyPrompt?.resolved = res ?? "settled"
                    }
                case .error(let err):
                    if self.activeBgTaskId != .invalid {
                        BackgroundTaskManager.shared.endTask(self.activeBgTaskId)
                        self.activeBgTaskId = .invalid
                    }
                    // Check if server completed the message before displaying an error
                    if let cId = self.currentChatId {
                        Task {
                            if let detail = try? await self.client.getChat(id: cId),
                               let lastMsg = detail.messages.last(where: { $0.role == "assistant" }),
                               (lastMsg.status == "done" || !lastMsg.content.isEmpty) {
                                self.messages = detail.messages
                                self.isGenerating = false
                                self.activeJobId = nil
                                self.contentPacer?.flushAll()
                                self.thinkingPacer?.flushAll()
                                return
                            }
                            self.contentPacer?.flushAll()
                            self.thinkingPacer?.flushAll()
                            self.messages[targetIdx].error = err
                            self.messages[targetIdx].status = "error"
                            self.isGenerating = false
                            self.activeJobId = nil
                        }
                    } else {
                        self.contentPacer?.flushAll()
                        self.thinkingPacer?.flushAll()
                        self.messages[targetIdx].error = err
                        self.messages[targetIdx].status = "error"
                        self.isGenerating = false
                        self.activeJobId = nil
                    }
                case .done(let st, let meta):
                    if self.activeBgTaskId != .invalid {
                        BackgroundTaskManager.shared.endTask(self.activeBgTaskId)
                        self.activeBgTaskId = .invalid
                    }
                    self.thinkingPacer?.flushAll()
                    self.contentPacer?.flushAll()
                    self.messages[targetIdx].status = st
                    let estTokens = max(1, Int(Double(streamTokenChars) / 3.6))
                    let elapsed = max(0.2, streamFirstTokenTime != nil ? Date().timeIntervalSince(streamFirstTokenTime!) : 1.0)
                    let liveTps = Double(estTokens) / elapsed
                    
                    let finalTps = (meta?.tps != nil && (meta?.tps ?? 0) > 0) ? meta!.tps! : (liveTps > 0 ? liveTps : 24.5)
                    let finalElapsed = (meta?.elapsed != nil && (meta?.elapsed ?? 0) > 0) ? meta!.elapsed! : elapsed
                    let finalTokens = (meta?.tokens != nil && (meta?.tokens ?? 0) > 0) ? meta!.tokens! : estTokens
                    
                    self.messages[targetIdx].meta = MessageMeta(
                        tps: finalTps,
                        ttft: meta?.ttft,
                        elapsed: finalElapsed,
                        thoughtS: meta?.thoughtS,
                        tokens: finalTokens,
                        promptTokens: meta?.promptTokens,
                        cachedTokens: meta?.cachedTokens,
                        maxContext: meta?.maxContext ?? 262144,
                        variant: meta?.variant,
                        model: meta?.model ?? "Hermes Agent",
                        finishReason: meta?.finishReason,
                        tools: meta?.tools ?? self.messages[targetIdx].toolCalls
                    )
                    self.isGenerating = false
                    self.activeJobId = nil
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    
                    if UIApplication.shared.applicationState != .active {
                        NotificationManager.shared.notifyJobComplete(chatId: self.currentChatId, preview: self.messages[targetIdx].content)
                    }
                    
                    // Immediately re-sync full canonical chat messages from server
                    if let cId = self.currentChatId {
                        Task {
                            if let detail = try? await self.client.getChat(id: cId) {
                                var updated = detail.messages
                                if let targetMeta = self.messages[targetIdx].meta,
                                   let lastIdx = updated.indices.last,
                                   updated[lastIdx].role == "assistant",
                                   (updated[lastIdx].meta?.tps == nil || (updated[lastIdx].meta?.tps ?? 0) <= 0) {
                                    updated[lastIdx].meta = targetMeta
                                }
                                if let streamedTools = self.messages[targetIdx].toolCalls, !streamedTools.isEmpty,
                                   let lastIdx = updated.indices.last,
                                   updated[lastIdx].role == "assistant",
                                   (updated[lastIdx].toolCalls == nil || updated[lastIdx].toolCalls?.isEmpty == true) {
                                    updated[lastIdx].toolCalls = streamedTools
                                }
                                self.messages = updated
                            }
                        }
                    }
                    Task { await self.loadChats() }
                case .status, .ping, .unknown:
                    break
                }
            }
        }
    }
    
    // MARK: - Voice Mode Streaming & Turn Execution
    public func sendVoiceTurn(text: String) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        self.isGenerating = true
        VoiceEngine.shared.prepareAssistantResponse()
        
        // Optimistic user message in active chat
        let tempUserMsg = ChatMessage(
            id: UUID().uuidString,
            chatId: currentChatId ?? "",
            role: "user",
            content: content,
            status: "done",
            createdAt: Date().timeIntervalSince1970
        )
        self.messages.append(tempUserMsg)
        
        if self.backend == .local {
            // 100% On-Device Airplane Mode Voice Processing!
            let assistantMsgId = UUID().uuidString
            let assistantMsg = ChatMessage(
                id: assistantMsgId,
                chatId: self.currentChatId ?? "",
                role: "assistant",
                content: "",
                status: "streaming",
                createdAt: Date().timeIntervalSince1970
            )
            self.messages.append(assistantMsg)
            
            Task {
                do {
                    var sentenceBuffer = ""
                    let sentenceDelimiters = CharacterSet(charactersIn: ".?!\n")
                    
                    let meta = try await LocalInferenceEngine.shared.generateStream(prompt: content, images: []) { [weak self] token in
                        guard let self = self else { return }
                        if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                            self.messages[idx].content += token
                        }
                        VoiceEngine.shared.appendAssistantText(token)
                        
                        sentenceBuffer += token
                        if let range = sentenceBuffer.rangeOfCharacter(from: sentenceDelimiters) {
                            let sentence = String(sentenceBuffer[..<range.upperBound])
                            sentenceBuffer = String(sentenceBuffer[range.upperBound...])
                            VoiceEngine.shared.speakOfflineSentence(sentence)
                        }
                    }
                    
                    let remaining = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !remaining.isEmpty {
                        VoiceEngine.shared.speakOfflineSentence(remaining)
                    }
                    
                    if let idx = self.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        self.messages[idx].status = "done"
                        self.messages[idx].meta = meta
                    }
                    self.isGenerating = false
                    VoiceEngine.shared.finishAssistantStream()
                    
                    let summary = ChatSummary(
                        id: self.currentChatId ?? UUID().uuidString,
                        title: self.currentChatTitle,
                        backend: "local",
                        hermesSessionId: nil,
                        created: Date().timeIntervalSince1970,
                        updated: Date().timeIntervalSince1970,
                        preview: String(content.prefix(50)),
                        messageCount: self.messages.count
                    )
                    LocalInferenceEngine.shared.saveLocalChat(summary: summary, messages: self.messages)
                    await self.loadChats()
                } catch {
                    self.isGenerating = false
                    VoiceEngine.shared.finishAssistantStream()
                    self.errorMessage = "Offline voice turn failed: \(error.localizedDescription)"
                }
            }
            return
        }
        
        Task {
            do {
                let res = try await client.send(
                    chatId: self.currentChatId,
                    content: content,
                    images: [],
                    backend: .strata,
                    effort: .off,
                    voiceMode: true
                )
                
                self.currentChatId = res.chat.id
                self.currentChatTitle = res.chat.title
                
                if let idx = self.messages.firstIndex(where: { $0.id == tempUserMsg.id }) {
                    self.messages[idx] = res.userMessage
                }
                self.messages.append(res.assistantMessage)
                
                self.streamVoiceJob(jobId: res.jobId, assistantMessageId: res.assistantMessage.id)
                await self.loadChats()
            } catch {
                self.isGenerating = false
                VoiceEngine.shared.finishAssistantStream()
                self.errorMessage = "Voice turn failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func streamVoiceJob(jobId: String, assistantMessageId: String) {
        self.streamTask?.cancel()
        self.activeJobId = jobId
        self.isGenerating = true
        
        if self.activeBgTaskId != .invalid {
            BackgroundTaskManager.shared.endTask(self.activeBgTaskId)
            self.activeBgTaskId = .invalid
        }
        self.activeBgTaskId = BackgroundTaskManager.shared.beginTask(name: "StrataVoiceJob-\(jobId)")
        
        var sentenceBuffer = ""
        let sentenceDelimiters = CharacterSet(charactersIn: ".?!\n")
        let clauseDelimiters = CharacterSet(charactersIn: ";:—\n")
        let voiceId = VoiceEngine.shared.selectedVoice
        var isCancelled = false
        var pendingSyntheses = 0
        var isStreamDone = false
        var currentChunkIndex = 0
        var nextChunkToEnqueue = 0
        var completedAudioChunks: [Int: Data] = [:]
        var hasSentFirstChunk = false
        
        func synthesizeAndEnqueue(_ text: String) {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !isCancelled else { return }
            
            let chunkIdx = currentChunkIndex
            currentChunkIndex += 1
            pendingSyntheses += 1
            
            Task { [weak self] in
                do {
                    let wavData = try await self?.client.synthesizeSpeech(text: cleaned, voice: voiceId, speed: 1.05) ?? Data()
                    await MainActor.run {
                        guard let self = self, !isCancelled else { return }
                        pendingSyntheses -= 1
                        completedAudioChunks[chunkIdx] = wavData
                        
                        // Flush completed audio chunks in strict sequential order (0, 1, 2, ...)
                        while let nextWav = completedAudioChunks[nextChunkToEnqueue] {
                            completedAudioChunks.removeValue(forKey: nextChunkToEnqueue)
                            if !nextWav.isEmpty {
                                VoiceEngine.shared.enqueueAudioChunk(nextWav)
                            }
                            nextChunkToEnqueue += 1
                        }
                        
                        if isStreamDone && pendingSyntheses == 0 {
                            VoiceEngine.shared.finishAssistantStream()
                            if self.activeJobId == jobId {
                                self.activeJobId = nil
                            }
                        }
                    }
                } catch {
                    print("Voice synthesis error for chunk #\(chunkIdx) '\(cleaned)': \(error)")
                    await MainActor.run {
                        guard let self = self, !isCancelled else { return }
                        pendingSyntheses -= 1
                        // Insert empty data on error so playback queue sequence doesn't stall
                        completedAudioChunks[chunkIdx] = Data()
                        
                        while let nextWav = completedAudioChunks[nextChunkToEnqueue] {
                            completedAudioChunks.removeValue(forKey: nextChunkToEnqueue)
                            if !nextWav.isEmpty {
                                VoiceEngine.shared.enqueueAudioChunk(nextWav)
                            }
                            nextChunkToEnqueue += 1
                        }
                        
                        if isStreamDone && pendingSyntheses == 0 {
                            VoiceEngine.shared.finishAssistantStream()
                            if self.activeJobId == jobId {
                                self.activeJobId = nil
                            }
                        }
                    }
                }
            }
        }
        
        func processBuffer() {
            while true {
                let trimmed = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { break }
                
                // 1. FIRST CHUNK (Instant time-to-first-sound):
                // Look for an introductory spoken opener ending with a comma, dash, or colon
                // within the first 1-5 words (e.g. "Hmm,", "Yeah,", "Well,", "Honestly,").
                if !hasSentFirstChunk {
                    if let firstCommaRange = sentenceBuffer.range(of: ",") ?? sentenceBuffer.range(of: "—") ?? sentenceBuffer.range(of: ":") {
                        let prefix = String(sentenceBuffer[..<firstCommaRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let prefixWords = prefix.split(separator: " ", omittingEmptySubsequences: true)
                        
                        if prefixWords.count >= 1 && prefixWords.count <= 5 && prefix.count >= 2 {
                            sentenceBuffer = String(sentenceBuffer[firstCommaRange.upperBound...])
                            hasSentFirstChunk = true
                            synthesizeAndEnqueue(prefix)
                            continue
                        }
                    }
                    
                    // If no introductory comma, wait for the first full sentence delimiter (.?! or \n)
                    if let sentenceRange = sentenceBuffer.rangeOfCharacter(from: sentenceDelimiters) {
                        let candidate = String(sentenceBuffer[..<sentenceRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        sentenceBuffer = String(sentenceBuffer[sentenceRange.upperBound...])
                        hasSentFirstChunk = true
                        synthesizeAndEnqueue(candidate)
                        continue
                    }
                    
                    // Keep accumulating tokens until the first sentence or opener is complete
                    break
                }
                
                // 2. SUBSEQUENT CHUNKS:
                // Primary: split on complete sentence ends (.?! or \n) for natural prosody
                if let sentenceRange = sentenceBuffer.rangeOfCharacter(from: sentenceDelimiters) {
                    let candidate = String(sentenceBuffer[..<sentenceRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    sentenceBuffer = String(sentenceBuffer[sentenceRange.upperBound...])
                    synthesizeAndEnqueue(candidate)
                    continue
                }
                
                // Secondary: for long compound sentences (> 12 words or > 70 chars),
                // split on a major clause pause (semicolon, dash, or comma with >= 6 words before it)
                let words = sentenceBuffer.split(separator: " ", omittingEmptySubsequences: true)
                if words.count >= 12 || sentenceBuffer.count >= 70 {
                    if let clauseRange = sentenceBuffer.rangeOfCharacter(from: clauseDelimiters) {
                        let candidate = String(sentenceBuffer[..<clauseRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        sentenceBuffer = String(sentenceBuffer[clauseRange.upperBound...])
                        synthesizeAndEnqueue(candidate)
                        continue
                    }
                    
                    if let commaRange = sentenceBuffer.range(of: ",") {
                        let prefix = String(sentenceBuffer[..<commaRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let prefixWordCount = prefix.split(separator: " ", omittingEmptySubsequences: true).count
                        if prefixWordCount >= 6 {
                            sentenceBuffer = String(sentenceBuffer[commaRange.upperBound...])
                            synthesizeAndEnqueue(prefix)
                            continue
                        }
                    }
                }
                
                // Otherwise, wait for the sentence to naturally finish
                break
            }
        }
        
        self.streamTask = client.streamJob(jobId: jobId) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                var idx = self.messages.firstIndex(where: { $0.id == assistantMessageId })
                if idx == nil {
                    idx = self.messages.firstIndex(where: { $0.jobId == jobId })
                }
                if idx == nil, let lastIdx = self.messages.indices.last, self.messages[lastIdx].role == "assistant" {
                    idx = lastIdx
                }
                guard let targetIdx = idx else { return }
                
                switch event.payload {
                case .content(let text):
                    self.messages[targetIdx].content += text
                    VoiceEngine.shared.appendAssistantText(text)
                    
                    sentenceBuffer += text
                    processBuffer()
                    
                case .done(let st, let meta):
                    if self.activeBgTaskId != .invalid {
                        BackgroundTaskManager.shared.endTask(self.activeBgTaskId)
                        self.activeBgTaskId = .invalid
                    }
                    self.messages[targetIdx].status = st
                    if let meta = meta {
                        self.messages[targetIdx].meta = meta
                    }
                    self.isGenerating = false
                    
                    if UIApplication.shared.applicationState != .active {
                        NotificationManager.shared.notifyJobComplete(chatId: self.currentChatId, preview: self.messages[targetIdx].content)
                    }
                    
                    let remaining = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !remaining.isEmpty {
                        synthesizeAndEnqueue(remaining)
                        sentenceBuffer = ""
                    }
                    isStreamDone = true
                    if pendingSyntheses == 0 {
                        VoiceEngine.shared.finishAssistantStream()
                        if self.activeJobId == jobId {
                            self.activeJobId = nil
                        }
                    }
                    Task { await self.loadChats() }
                case .error(let err):
                    if self.activeBgTaskId != .invalid {
                        BackgroundTaskManager.shared.endTask(self.activeBgTaskId)
                        self.activeBgTaskId = .invalid
                    }
                    isCancelled = true
                    self.messages[targetIdx].status = "error"
                    self.messages[targetIdx].error = err
                    self.isGenerating = false
                    self.activeJobId = nil
                    isStreamDone = true
                    VoiceEngine.shared.finishAssistantStream()
                default:
                    break
                }
            }
        }
    }
}

