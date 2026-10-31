import Foundation
import Network

public struct ParsedToolCall {
    public let name: String
    public let arguments: [String: Any]
    public let rawCallString: String
}

public class LocalToolEngine {
    public static let shared = LocalToolEngine()
    
    private init() {}
    
    public var toolInstructions: String {
        return """
        You are Strata Chat running locally on iPhone 17 Pro Metal.
        You have direct access to tools to create files and search the web.
        
        Available tools:
        1. create_pdf(filename: string, title: string, content: string)
           - Call this when the user specifically asks to create, make, or save a PDF file (e.g. "make this into a PDF", "make a PDF of this").
           - Write complete, well-formatted markdown for the document content.
        2. create_word_document(filename: string, title: string, content: string)
           - Call this when the user asks for a Word file (.docx).
        3. web_search(query: string)
           - Call this when the user asks for current news, live web info, or facts that require searching the internet.
        
        RULE: If the user does NOT explicitly request a PDF/Word file or web search, answer normally in chat without calling any tool.
        When calling a tool, output exactly this format:
        <tool_call>
        {"name": "tool_name", "arguments": {"filename": "file.pdf", "title": "Doc Title", "content": "# Markdown content..."}}
        </tool_call>
        """
    }
    
    // MARK: - Parse Tool Calls
    public func parseToolCalls(from text: String) -> [ParsedToolCall] {
        var results: [ParsedToolCall] = []
        
        // 1. Look for <tool_call> ... </tool_call>
        let pattern = "<tool_call>([\\s\\S]*?)</tool_call>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                if match.numberOfRanges > 1 {
                    let jsonRange = match.range(at: 1)
                    let fullRange = match.range(at: 0)
                    let jsonString = nsString.substring(with: jsonRange).trimmingCharacters(in: .whitespacesAndNewlines)
                    let rawCall = nsString.substring(with: fullRange)
                    
                    if let parsed = parseJSON(jsonString, rawCall: rawCall) {
                        results.append(parsed)
                    }
                }
            }
        }
        
        // 2. Look for ```tool_call ... ```
        if results.isEmpty {
            let mdPattern = "```(?:tool_call|json)\\s*\\n([\\s\\S]*?)\\n```"
            if let mdRegex = try? NSRegularExpression(pattern: mdPattern, options: []) {
                let nsString = text as NSString
                let matches = mdRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
                
                for match in matches {
                    if match.numberOfRanges > 1 {
                        let jsonRange = match.range(at: 1)
                        let fullRange = match.range(at: 0)
                        let jsonString = nsString.substring(with: jsonRange).trimmingCharacters(in: .whitespacesAndNewlines)
                        let rawCall = nsString.substring(with: fullRange)
                        
                        if let parsed = parseJSON(jsonString, rawCall: rawCall) {
                            results.append(parsed)
                        }
                    }
                }
            }
        }
        
        return results
    }
    
    private func parseJSON(_ jsonString: String, rawCall: String) -> ParsedToolCall? {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = dict["name"] as? String else {
            return nil
        }
        let args = (dict["arguments"] as? [String: Any]) ?? [:]
        return ParsedToolCall(name: name, arguments: args, rawCallString: rawCall)
    }
    
    // MARK: - Execute Tool
    public func executeTool(_ call: ParsedToolCall) async -> (resultText: String, generatedFile: GeneratedFileInfo?) {
        switch call.name {
        case "create_pdf":
            let filename = (call.arguments["filename"] as? String) ?? "Document.pdf"
            let title = (call.arguments["title"] as? String) ?? "Document"
            let content = (call.arguments["content"] as? String) ?? ""
            
            do {
                let file = try DocumentGenerator.shared.createPDF(filename: filename, title: title, markdown: content)
                return ("Created PDF document '\(file.filename)'. Ready for preview or download.", file)
            } catch {
                return ("Failed to create PDF document: \(error.localizedDescription)", nil)
            }
            
        case "create_word_document", "create_word_doc":
            let filename = (call.arguments["filename"] as? String) ?? "Document.docx"
            let title = (call.arguments["title"] as? String) ?? "Document"
            let content = (call.arguments["content"] as? String) ?? ""
            
            do {
                let file = try DocumentGenerator.shared.createWordDoc(filename: filename, title: title, markdown: content)
                return ("Created Microsoft Word document '\(file.filename)'. Ready for preview or download.", file)
            } catch {
                return ("Failed to create Word document: \(error.localizedDescription)", nil)
            }
            
        case "web_search":
            let query = (call.arguments["query"] as? String) ?? ""
            guard !query.isEmpty else {
                return ("Web search query was empty.", nil)
            }
            let searchResult = await performWebSearch(query: query)
            return (searchResult, nil)
            
        default:
            return ("Unknown tool '\(call.name)'.", nil)
        }
    }
    
    // MARK: - Web Search (Online search with Airplane Mode fallback)
    private func performWebSearch(query: String) async -> String {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else {
            return "Invalid search query."
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 6.0
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return "Web search received unexpected HTTP response."
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "Failed to parse search response."
            }
            
            var snippets: [String] = []
            if let heading = json["Heading"] as? String, !heading.isEmpty {
                snippets.append("Title: \(heading)")
            }
            if let abstract = json["AbstractText"] as? String, !abstract.isEmpty {
                snippets.append("Summary: \(abstract)")
            }
            if let related = json["RelatedTopics"] as? [[String: Any]] {
                for topic in related.prefix(3) {
                    if let text = topic["Text"] as? String, !text.isEmpty {
                        snippets.append("• \(text)")
                    }
                }
            }
            
            if snippets.isEmpty {
                return "Search results for '\(query)': No immediate summary available on DuckDuckGo."
            }
            return "Search Results for '\(query)':\n" + snippets.joined(separator: "\n")
        } catch {
            // Check if device is in Airplane Mode or offline
            return "Web search unavailable: Device is offline or in Airplane Mode. Answering from on-device model weights."
        }
    }
}
