import Foundation

public enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(String)
    case networkError(Error)
    case conflict(jobId: String?, assistantMessageId: String?)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .unauthorized: return "Unauthorized. Please check your password."
        case .serverError(let msg): return msg
        case .networkError(let err): return err.localizedDescription
        case .conflict: return "This chat is still generating."
        }
    }
}

public class APIClient {
    public static let shared = APIClient()
    private let config = ServerConfig.shared
    private let session = URLSession(configuration: .default)
    private let streamSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 3600
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()
    
    private init() {}
    
    public func ensureAuthenticated() async {
        if config.isAuthenticated { return }
        if !config.savedPassword.isEmpty {
            _ = try? await login(password: config.savedPassword)
        }
    }
    
    private func makeRequest(path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 25) throws -> URLRequest {
        guard let baseURL = config.cleanBaseURL else {
            throw APIError.invalidURL
        }
        let url = baseURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        
        if let token = config.authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("mc_session=\(token)", forHTTPHeaderField: "Cookie")
            req.setValue(token, forHTTPHeaderField: "X-Session-Token")
        }
        req.setValue(config.deviceId, forHTTPHeaderField: "X-Device-ID")
        if E2EEManager.shared.isEnabled {
            req.setValue("true", forHTTPHeaderField: "X-E2EE")
        }
        if let body = body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }
    
    private func sendRequest(path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 25) async throws -> (Data, HTTPURLResponse) {
        do {
            let req = try makeRequest(path: path, method: method, body: body, timeout: timeout)
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.serverError("No response from server")
            }
            
            // Auto re-authenticate on 401 Unauthorized
            if http.statusCode == 401 && path != "/api/login" && !config.savedPassword.isEmpty {
                print("[APIClient] Session 401 on \(path). Attempting re-authentication with saved credentials...")
                await MainActor.run {
                    config.authToken = nil
                }
                if (try? await login(password: config.savedPassword)) != nil {
                    if let retryReq = try? makeRequest(path: path, method: method, body: body, timeout: timeout),
                       let (retryData, retryResp) = try? await session.data(for: retryReq),
                       let retryHttp = retryResp as? HTTPURLResponse {
                        return (retryData, retryHttp)
                    }
                }
            }
            
            // If remote tunnel gives 530/502 (tunnel died), attempt Gist auto-sync once
            if (http.statusCode == 530 || (http.statusCode >= 502 && http.statusCode <= 504)) && config.isUsingRemote {
                print("[APIClient] Remote tunnel returned HTTP \(http.statusCode). Trying Gist auto-sync...")
                if await config.syncTunnelFromGist() {
                    if let retryReq = try? makeRequest(path: path, method: method, body: body, timeout: timeout),
                       let (retryData, retryResp) = try? await session.data(for: retryReq),
                       let retryHttp = retryResp as? HTTPURLResponse, retryHttp.statusCode < 500 {
                        return (retryData, retryHttp)
                    }
                }
            }
            
            return (data, http)
        } catch let err as URLError where isConnectionError(err) {
            if config.isUsingRemote {
                print("[APIClient] Connection error to remote tunnel. Trying Gist auto-sync...")
                if await config.syncTunnelFromGist() {
                    if let retryReq = try? makeRequest(path: path, method: method, body: body, timeout: timeout),
                       let (retryData, retryResp) = try? await session.data(for: retryReq),
                       let retryHttp = retryResp as? HTTPURLResponse, retryHttp.statusCode < 500 {
                        return (retryData, retryHttp)
                    }
                }
            }
            throw err
        }
    }
    
    private func isConnectionError(_ err: URLError) -> Bool {
        return err.code == .cannotConnectToHost ||
               err.code == .cannotFindHost ||
               err.code == .dnsLookupFailed
    }
    
    private func decodeResponse<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["e2ee"] as? Bool == true,
           let iv = json["iv"] as? String,
           let cipher = json["data"] as? String {
            guard let decrypted = E2EEManager.shared.decrypt(iv: iv, data: cipher) else {
                throw APIError.serverError("Failed to decrypt server response (check passphrase)")
            }
            return try JSONDecoder().decode(T.self, from: decrypted)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    public func getE2EEStatus() async -> Bool {
        do {
            let (data, http) = try await sendRequest(path: "/api/e2ee/status")
            guard http.statusCode == 200 else { return false }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return (json?["enabled"] as? Bool) == true
        } catch {
            return false
        }
    }
    
    public func login(password: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: [
            "password": password,
            "device_id": config.deviceId
        ])
        let (data, http) = try await sendRequest(path: "/api/login", method: "POST", body: body)
        
        if http.statusCode == 401 {
            throw APIError.unauthorized
        }
        if http.statusCode >= 400 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Login failed (\(http.statusCode))"
            throw APIError.serverError(msg)
        }
        
        var token: String? = nil
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tok = json["token"] as? String {
            token = tok
        }
        
        if token == nil, let cookies = HTTPCookie.cookies(withResponseHeaderFields: http.allHeaderFields as? [String: String] ?? [:], for: http.url ?? URL(string: config.baseURLString)!) as [HTTPCookie]? {
            token = cookies.first(where: { $0.name == "mc_session" })?.value
        }
        
        guard let finalToken = token else {
            throw APIError.serverError("Server did not return a session token")
        }
        
        await MainActor.run {
            config.authToken = finalToken
            config.savedPassword = password
        }
        return finalToken
    }
    
    public func checkSession() async -> Bool {
        do {
            let (data, http) = try await sendRequest(path: "/api/session")
            guard http.statusCode == 200 else { return false }
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return (json?["authenticated"] as? Bool) == true
        } catch {
            return false
        }
    }
    
    public func getStatus() async throws -> ServerStatus {
        await ensureAuthenticated()
        let (data, http) = try await sendRequest(path: "/api/status", timeout: 8)
        guard http.statusCode == 200 else {
            throw APIError.serverError("Failed to fetch status")
        }
        return try JSONDecoder().decode(ServerStatus.self, from: data)
    }
    
    public func getHardware() async throws -> HardwareInfo {
        await ensureAuthenticated()
        let (data, http) = try await sendRequest(path: "/api/hardware", timeout: 8)
        guard http.statusCode == 200 else {
            throw APIError.serverError("Failed to fetch hardware telemetry")
        }
        // This endpoint goes through the E2EE envelope like the chat endpoints, because the client
        // always sends `X-E2EE: true`. It must therefore use decodeResponse. A raw JSONDecoder
        // happily maps `{e2ee, iv, data}` onto an all-optional HardwareInfo - unknown keys ignored,
        // every field nil - so the sheet rendered a wall of em-dashes with no error at all.
        let hw: HardwareInfo = try decodeResponse(HardwareInfo.self, from: data)
        guard !(hw.gpus ?? []).isEmpty || hw.memory != nil || hw.cpu != nil else {
            throw APIError.serverError("Telemetry payload came back empty")
        }
        return hw
    }

    public func warmup() async throws {
        await ensureAuthenticated()
        _ = try await sendRequest(path: "/api/warmup", method: "POST", timeout: 60)
    }
    
    public func unload() async throws {
        await ensureAuthenticated()
        let (data, http) = try await sendRequest(path: "/api/unload", method: "POST", timeout: 120)
        if http.statusCode >= 400 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Unload failed"
            throw APIError.serverError(msg)
        }
    }
    
    public func switchVariant(variant: String) async throws {
        await ensureAuthenticated()
        let body = try JSONSerialization.data(withJSONObject: ["variant": variant])
        let (data, http) = try await sendRequest(path: "/api/switch", method: "POST", body: body, timeout: 120)
        if http.statusCode >= 400 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Switch failed"
            throw APIError.serverError(msg)
        }
    }
    
    public func listChats(query: String? = nil) async throws -> [ChatSummary] {
        await ensureAuthenticated()
        var path = "/api/chats"
        if let q = query, !q.isEmpty {
            path += "?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        let (data, http) = try await sendRequest(path: path)
        guard http.statusCode == 200 else {
            throw APIError.serverError("Failed to fetch chats")
        }
        return try decodeResponse([ChatSummary].self, from: data)
    }
    
    public func getChat(id: String) async throws -> ChatDetail {
        await ensureAuthenticated()
        let (data, http) = try await sendRequest(path: "/api/chats/\(id)")
        guard http.statusCode == 200 else {
            throw APIError.serverError("Failed to fetch chat")
        }
        return try decodeResponse(ChatDetail.self, from: data)
    }
    
    public func renameChat(id: String, title: String) async throws {
        await ensureAuthenticated()
        let body = try JSONSerialization.data(withJSONObject: ["title": title])
        _ = try await sendRequest(path: "/api/chats/\(id)", method: "PATCH", body: body)
    }
    
    public func deleteChat(id: String) async throws {
        await ensureAuthenticated()
        _ = try await sendRequest(path: "/api/chats/\(id)", method: "DELETE")
    }
    
    public func send(chatId: String?, content: String, images: [String], backend: Backend, effort: EffortLevel = .medium, voiceMode: Bool = false, mediaIds: [String] = []) async throws -> SendResponse {
        await ensureAuthenticated()
        var dict: [String: Any] = [
            "content": content,
            "images": images,
            "media_ids": mediaIds,
            "backend": backend.rawValue,
            "voice_mode": voiceMode,
            "settings": [
                "effort": effort.rawValue,
                "thinking": effort.rawValue
            ]
        ]
        if let cId = chatId {
            dict["chat_id"] = cId
        }
        let body: Data
        if E2EEManager.shared.isEnabled, let encPayload = E2EEManager.shared.encrypt(dict: dict) {
            body = try JSONSerialization.data(withJSONObject: encPayload)
        } else {
            body = try JSONSerialization.data(withJSONObject: dict)
        }
        let (data, http) = try await sendRequest(path: "/api/send", method: "POST", body: body, timeout: 180)
        if http.statusCode == 409 {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let detail = obj["detail"] as? [String: Any] {
                    let jId = detail["job_id"] as? String
                    let asstId = detail["assistant_message_id"] as? String
                    throw APIError.conflict(jobId: jId, assistantMessageId: asstId)
                } else if let jId = obj["job_id"] as? String {
                    let asstId = obj["assistant_message_id"] as? String
                    throw APIError.conflict(jobId: jId, assistantMessageId: asstId)
                }
            }
            throw APIError.conflict(jobId: nil, assistantMessageId: nil)
        }
        guard http.statusCode == 200 else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Failed to send message"
            throw APIError.serverError(msg)
        }
        return try decodeResponse(SendResponse.self, from: data)
    }
    
    /// Upload a phone clip inside the same AES-GCM envelope the chat payloads use, and return the
    /// server manifest that describes the sampled frames.
    public func uploadVideo(data: Data, container: String) async throws -> [String: Any] {
        await ensureAuthenticated()
        guard E2EEManager.shared.isEnabled, let sealed = E2EEManager.shared.encrypt(data: data) else {
            throw APIError.serverError("Video needs the encryption key. Set a passphrase in Settings.")
        }
        let payload: [String: Any] = [
            "iv": sealed["iv"] as? String ?? "",
            "data": sealed["data"] as? String ?? "",
            "container": container
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (response, http) = try await sendRequest(path: "/api/media/video", method: "POST", body: body, timeout: 300)
        let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any]
        guard http.statusCode == 200 else {
            throw APIError.serverError((json?["detail"] as? String) ?? "Video upload failed")
        }
        return json?["media"] as? [String: Any] ?? [:]
    }
    
    public func getVoices() async throws -> [VoiceOption] {
        await ensureAuthenticated()
        let (data, http) = try await sendRequest(path: "/api/voice/voices")
        guard http.statusCode == 200 else {
            return []
        }
        let res = try JSONDecoder().decode(VoiceListResponse.self, from: data)
        return res.voices
    }
    
    public func synthesizeSpeech(text: String, voice: String = "af_heart", speed: Float = 1.05) async throws -> Data {
        await ensureAuthenticated()
        var dict: [String: Any] = [
            "text": text,
            "voice": voice,
            "speed": speed
        ]
        let body: Data
        if E2EEManager.shared.isEnabled, let encPayload = E2EEManager.shared.encrypt(dict: dict) {
            body = try JSONSerialization.data(withJSONObject: encPayload)
        } else {
            body = try JSONSerialization.data(withJSONObject: dict)
        }
        let (data, http) = try await sendRequest(path: "/api/voice/tts", method: "POST", body: body)
        guard http.statusCode == 200 else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Voice synthesis failed (\(http.statusCode))"
            throw APIError.serverError(msg)
        }
        return data
    }
    
    public func regenerate(chatId: String, backend: Backend, effort: EffortLevel = .medium) async throws -> RegenResponse {
        await ensureAuthenticated()
        let dict: [String: Any] = [
            "backend": backend.rawValue,
            "settings": [
                "effort": effort.rawValue,
                "thinking": effort.rawValue
            ]
        ]
        let body: Data
        if E2EEManager.shared.isEnabled, let encPayload = E2EEManager.shared.encrypt(dict: dict) {
            body = try JSONSerialization.data(withJSONObject: encPayload)
        } else {
            body = try JSONSerialization.data(withJSONObject: dict)
        }
        let (data, http) = try await sendRequest(path: "/api/chats/\(chatId)/regenerate", method: "POST", body: body, timeout: 180)
        if http.statusCode == 409 {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let detail = obj["detail"] as? [String: Any] {
                    let jId = detail["job_id"] as? String
                    let asstId = detail["assistant_message_id"] as? String
                    throw APIError.conflict(jobId: jId, assistantMessageId: asstId)
                } else if let jId = obj["job_id"] as? String {
                    let asstId = obj["assistant_message_id"] as? String
                    throw APIError.conflict(jobId: jId, assistantMessageId: asstId)
                }
            }
            throw APIError.conflict(jobId: nil, assistantMessageId: nil)
        }
        guard http.statusCode == 200 else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Failed to regenerate"
            throw APIError.serverError(msg)
        }
        return try decodeResponse(RegenResponse.self, from: data)
    }
    
    public func editMessage(chatId: String, messageId: String, content: String, backend: Backend, effort: EffortLevel = .medium) async throws -> EditResponse {
        await ensureAuthenticated()
        let dict: [String: Any] = [
            "message_id": messageId,
            "content": content,
            "backend": backend.rawValue,
            "settings": [
                "effort": effort.rawValue,
                "thinking": effort.rawValue
            ]
        ]
        let body: Data
        if E2EEManager.shared.isEnabled, let encPayload = E2EEManager.shared.encrypt(dict: dict) {
            body = try JSONSerialization.data(withJSONObject: encPayload)
        } else {
            body = try JSONSerialization.data(withJSONObject: dict)
        }
        let (data, http) = try await sendRequest(path: "/api/chats/\(chatId)/edit", method: "POST", body: body, timeout: 180)
        guard http.statusCode == 200 else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Failed to edit message"
            throw APIError.serverError(msg)
        }
        return try decodeResponse(EditResponse.self, from: data)
    }
    
    public func undo(chatId: String) async throws -> ChatDetail {
        await ensureAuthenticated()
        let (data, http) = try await sendRequest(path: "/api/chats/\(chatId)/undo", method: "POST", body: nil)
        guard http.statusCode == 200 else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Failed to undo turn"
            throw APIError.serverError(msg)
        }
        struct UndoResp: Codable {
            let ok: Bool
            let chat: ChatDetail
        }
        let res = try decodeResponse(UndoResp.self, from: data)
        return res.chat
    }
    
    public func compactChat(chatId: String) async throws -> ChatDetail {
        await ensureAuthenticated()
        let (data, http) = try await sendRequest(path: "/api/chats/\(chatId)/compact", method: "POST", body: nil)
        guard http.statusCode == 200 else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String ?? "Failed to compact conversation"
            throw APIError.serverError(msg)
        }
        struct CompactResp: Codable {
            let ok: Bool
            let chat: ChatDetail
        }
        let res = try decodeResponse(CompactResp.self, from: data)
        return res.chat
    }
    
    public func cancelJob(jobId: String) async {
        _ = try? await sendRequest(path: "/api/jobs/\(jobId)/cancel", method: "POST", timeout: 15)
    }
    
    public func stopChat(chatId: String) async {
        _ = try? await sendRequest(path: "/api/chats/\(chatId)/stop", method: "POST", timeout: 15)
    }
    
    public func submitApproval(jobId: String, promptId: String, choice: String) async throws {
        await ensureAuthenticated()
        let body = try JSONSerialization.data(withJSONObject: [
            "prompt_id": promptId,
            "choice": choice
        ])
        _ = try await sendRequest(path: "/api/jobs/\(jobId)/approval", method: "POST", body: body)
    }
    
    public func submitClarify(jobId: String, promptId: String, answer: String) async throws {
        await ensureAuthenticated()
        let body = try JSONSerialization.data(withJSONObject: [
            "prompt_id": promptId,
            "answer": answer
        ])
        _ = try await sendRequest(path: "/api/jobs/\(jobId)/clarify", method: "POST", body: body)
    }
    
    // Server-Sent Events reader using unbuffered URLSessionDataDelegate.
    // Cloudflare quick tunnels hold a streaming response until it closes, so we request short
    // "burst" responses (X-Stream-Mode: burst) and reconnect right away, resuming with Last-Event-ID.
    // This also makes the stream survive network switches (Wi-Fi <-> LTE) and brief drops.
    public func streamJob(jobId: String, onEvent: @escaping (SSEEvent) -> Void) -> Task<Void, Never> {
        return Task {
            let state = SSEStreamState()
            var consecutiveFailures = 0
            let maxFailures = 150
            
            // One session for the whole stream so the TLS/HTTP2 connection stays warm between bursts
            // (a new handshake per burst would add ~0.5s of latency on cellular).
            let sessionConfig = URLSessionConfiguration.ephemeral
            sessionConfig.timeoutIntervalForRequest = 60
            sessionConfig.timeoutIntervalForResource = 120
            sessionConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            sessionConfig.urlCache = nil
            sessionConfig.httpShouldUsePipelining = false
            sessionConfig.waitsForConnectivity = true
            let session = URLSession(configuration: sessionConfig)
            defer { session.finishTasksAndInvalidate() }
            
            while !Task.isCancelled && !state.finished {
                await self.ensureAuthenticated()
                guard var req = try? self.makeRequest(path: "/api/jobs/\(jobId)/events") else {
                    onEvent(SSEEvent(id: nil, payload: .error("Invalid server URL")))
                    return
                }
                req.timeoutInterval = 60
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                req.setValue("burst", forHTTPHeaderField: "X-Stream-Mode")
                if state.nextOffset > 0 {
                    req.setValue(String(state.nextOffset - 1), forHTTPHeaderField: "Last-Event-ID")
                }
                
                state.resetAttempt()
                var activeTask: URLSessionDataTask?
                var attemptError: Error?
                
                await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        let delegate = SSEStreamDelegate(
                            state: state,
                            onEvent: { ev in onEvent(ev) },
                            onComplete: { error in
                                attemptError = error
                                continuation.resume()
                            }
                        )
                        let task = session.dataTask(with: req)
                        task.delegate = delegate
                        activeTask = task
                        task.resume()
                    }
                } onCancel: {
                    activeTask?.cancel()
                }
                
                if Task.isCancelled || state.finished { break }
                
                let status = state.statusCode
                if status == 404 {
                    if state.receivedEvents > 0 {
                        // Job completed on server and expired from memory after delivering events
                        onEvent(SSEEvent(id: nil, payload: .done(status: "done", meta: nil)))
                        return
                    }
                    onEvent(SSEEvent(id: nil, payload: .error("This response is no longer available on the server.")))
                    return
                }
                if status == 401 || status == 403 {
                    if !self.config.savedPassword.isEmpty {
                        _ = try? await self.login(password: self.config.savedPassword)
                    }
                }
                
                let gotData = state.receivedEvents > 0
                if gotData && status < 400 {
                    consecutiveFailures = 0
                    try? await Task.sleep(nanoseconds: 2_000_000)   // reconnect immediately (2ms)
                } else {
                    consecutiveFailures += 1
                    if consecutiveFailures > maxFailures {
                        let reason = (attemptError as? URLError)?.localizedDescription ?? "Connection lost"
                        onEvent(SSEEvent(id: nil, payload: .error(reason)))
                        return
                    }
                    let backoff = min(3.0, 0.4 * Double(consecutiveFailures))
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                }
            }
        }
    }
    
    // MARK: - Remote Power Control (E2EE Authenticated)
    public func triggerPowerAction(_ action: String, confirm: Bool = false) async throws -> String {
        await ensureAuthenticated()
        
        var payload: [String: Any] = [
            "action": action,
            "timestamp": Date().timeIntervalSince1970
        ]
        if confirm {
            payload["confirm"] = true
        }
        
        let bodyData: Data
        if E2EEManager.shared.isEnabled, let encrypted = E2EEManager.shared.encrypt(dict: payload) {
            bodyData = try JSONSerialization.data(withJSONObject: encrypted)
        } else {
            payload["e2ee"] = false
            bodyData = try JSONSerialization.data(withJSONObject: payload)
        }
        
        let (data, response) = try await sendRequest(path: "/api/power/action", method: "POST", body: bodyData)
        guard response.statusCode == 200 else {
            if let errJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errJson["detail"] as? String {
                throw APIError.serverError(detail)
            }
            throw APIError.serverError("Power action failed (\(response.statusCode))")
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if json["e2ee"] as? Bool == true,
               let iv = json["iv"] as? String,
               let encData = json["data"] as? String,
               let decryptedData = E2EEManager.shared.decrypt(iv: iv, data: encData),
               let decJson = try? JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
               let msg = decJson["message"] as? String {
                return msg
            }
            return json["message"] as? String ?? "Power command executed."
        }
        return "Command received."
    }
}

/// Thread-safe progress shared between the reconnect loop and the URLSession delegate queue.
private final class SSEStreamState: @unchecked Sendable {
    private let lock = NSLock()
    private var _nextOffset = 0
    private var _finished = false
    private var _receivedEvents = 0
    private var _statusCode = 0

    var nextOffset: Int { lock.lock(); defer { lock.unlock() }; return _nextOffset }
    var finished: Bool { lock.lock(); defer { lock.unlock() }; return _finished }
    var receivedEvents: Int { lock.lock(); defer { lock.unlock() }; return _receivedEvents }
    var statusCode: Int { lock.lock(); defer { lock.unlock() }; return _statusCode }

    func resetAttempt() { lock.lock(); _receivedEvents = 0; _statusCode = 0; lock.unlock() }
    func setStatus(_ code: Int) { lock.lock(); _statusCode = code; lock.unlock() }
    func record(_ ev: SSEEvent) {
        lock.lock()
        if let id = ev.id { _nextOffset = max(_nextOffset, id + 1) }
        switch ev.payload {
        case .ping, .unknown: break
        case .done: _receivedEvents += 1; _finished = true
        default: _receivedEvents += 1
        }
        lock.unlock()
    }
}

private final class SSEStreamDelegate: NSObject, URLSessionDataDelegate {
    private var buffer = Data()
    private let separator = Data("\n\n".utf8)
    private let state: SSEStreamState
    private let onEvent: (SSEEvent) -> Void
    private let onComplete: (Error?) -> Void
    
    init(state: SSEStreamState, onEvent: @escaping (SSEEvent) -> Void, onComplete: @escaping (Error?) -> Void) {
        self.state = state
        self.onEvent = onEvent
        self.onComplete = onComplete
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            state.setStatus(http.statusCode)
            if http.statusCode >= 400 {
                // The reconnect loop decides whether this is fatal (404) or transient.
                completionHandler(.cancel)
                return
            }
        }
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        drain()
    }
    
    private func drain() {
        while let range = buffer.range(of: separator) {
            let blockData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            guard !blockData.isEmpty, let block = String(data: blockData, encoding: .utf8) else { continue }
            if let ev = SSEEvent.parse(raw: block) {
                state.record(ev)
                onEvent(ev)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        drain()
        if !buffer.isEmpty, let block = String(data: buffer, encoding: .utf8), let ev = SSEEvent.parse(raw: block) {
            state.record(ev)
            onEvent(ev)
        }
        buffer.removeAll()
        onComplete(error)
    }
}
