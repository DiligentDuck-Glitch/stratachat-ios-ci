import Foundation

public enum SSEEventPayload {
    case phase(String)
    case prefill(read: Int, total: Int, tokS: Double?)
    case content(String)
    case reasoning(String)
    case status(String)
    case toolProgress(id: String, tool: String, status: String)
    case approvalPrompt(id: String, command: String?, reason: String?)
    case clarifyPrompt(id: String, question: String, choices: [String]?)
    case controlSettled(id: String, resolution: String?)
    case error(String)
    case done(status: String, meta: MessageMeta?)
    case ping
    case unknown
}

public struct SSEEvent {
    public let id: Int?
    public let payload: SSEEventPayload
    
    public static func parse(raw: String) -> SSEEvent? {
        var id: Int? = nil
        var dataLines: [String] = []
        
        var sawComment = false
        let lines = raw.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix(":") {
                sawComment = true
                continue
            }
            if line.hasPrefix("id:") {
                let idStr = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                id = Int(idStr)
            } else if line.hasPrefix("data:") {
                let dataStr = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                dataLines.append(dataStr)
            }
        }
        
        guard !dataLines.isEmpty else {
            return sawComment ? SSEEvent(id: nil, payload: .ping) : nil
        }
        let fullData = dataLines.joined(separator: "\n")
        guard let data = fullData.data(using: .utf8),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        if json["e2ee"] as? Bool == true,
           let iv = json["iv"] as? String,
           let cipherData = json["data"] as? String,
           let decryptedData = E2EEManager.shared.decrypt(iv: iv, data: cipherData),
           let inner = try? JSONSerialization.jsonObject(with: decryptedData) as? [String: Any] {
            json = inner
        }
        
        guard let type = json["type"] as? String else {
            return nil
        }
        
        switch type {
        case "phase":
            let ph = json["phase"] as? String ?? ""
            return SSEEvent(id: id, payload: .phase(ph))
        case "prefill":
            // Live engine stats: only emitted when Strata is actually reading the prompt.
            guard let total = json["total"] as? Int, total > 0 else { return nil }
            let read = json["read"] as? Int ?? 0
            let tokS = (json["tok_s"] as? Double) ?? (json["tok_s"] as? Int).map { Double($0) }
            return SSEEvent(id: id, payload: .prefill(read: read, total: total, tokS: tokS))
        case "content":
            let text = json["text"] as? String ?? ""
            return SSEEvent(id: id, payload: .content(text))
        case "reasoning":
            let text = json["text"] as? String ?? ""
            return SSEEvent(id: id, payload: .reasoning(text))
        case "status":
            let text = json["text"] as? String ?? ""
            return SSEEvent(id: id, payload: .status(text))
        case "tool_progress", "tool":
            let toolObj = json["tool"] as? [String: Any]
            let toolId = (json["id"] as? String) ?? (toolObj?["id"] as? String) ?? UUID().uuidString
            let tool = (json["name"] as? String) ?? (json["tool"] as? String) ?? (toolObj?["name"] as? String) ?? (toolObj?["tool"] as? String) ?? "tool"
            let status = (json["status"] as? String) ?? (toolObj?["status"] as? String) ?? "running"
            return SSEEvent(id: id, payload: .toolProgress(id: toolId, tool: tool, status: status))
        case "control":
            let ctrl = (json["control"] as? [String: Any]) ?? json
            let kind = ctrl["kind"] as? String ?? "approval"
            let promptId = (ctrl["prompt_id"] as? String) ?? (ctrl["id"] as? String) ?? (ctrl["request_id"] as? String) ?? ""
            if kind == "clarify" {
                let question = (ctrl["question"] as? String) ?? ""
                let choices = ctrl["choices"] as? [String]
                return SSEEvent(id: id, payload: .clarifyPrompt(id: promptId, question: question, choices: choices))
            } else {
                let cmd = ctrl["command"] as? String
                let reason = (ctrl["description"] as? String) ?? (ctrl["reason"] as? String)
                return SSEEvent(id: id, payload: .approvalPrompt(id: promptId, command: cmd, reason: reason))
            }
        case "control_settled":
            let promptId = (json["prompt_id"] as? String) ?? (json["id"] as? String) ?? ""
            let res = json["resolution"] as? String
            return SSEEvent(id: id, payload: .controlSettled(id: promptId, resolution: res))
        case "approval_prompt":
            let promptId = (json["id"] as? String) ?? (json["prompt_id"] as? String) ?? ""
            let cmd = json["command"] as? String
            let reason = (json["reason"] as? String) ?? (json["description"] as? String)
            return SSEEvent(id: id, payload: .approvalPrompt(id: promptId, command: cmd, reason: reason))
        case "clarify_prompt":
            let promptId = (json["id"] as? String) ?? (json["prompt_id"] as? String) ?? ""
            let question = json["question"] as? String ?? ""
            let choices = json["choices"] as? [String]
            return SSEEvent(id: id, payload: .clarifyPrompt(id: promptId, question: question, choices: choices))
        case "error":
            let msg = json["message"] as? String ?? "Generation error"
            return SSEEvent(id: id, payload: .error(msg))
        case "done":
            let st = json["status"] as? String ?? "done"
            var metaObj: MessageMeta? = nil
            if let m = json["meta"] as? [String: Any],
               let mData = try? JSONSerialization.data(withJSONObject: m),
               let parsed = try? JSONDecoder().decode(MessageMeta.self, from: mData) {
                metaObj = parsed
            }
            return SSEEvent(id: id, payload: .done(status: st, meta: metaObj))
        default:
            return SSEEvent(id: id, payload: .unknown)
        }
    }
}
