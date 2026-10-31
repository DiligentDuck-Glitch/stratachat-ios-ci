import SwiftUI

private struct MessageContentChunk: Identifiable {
    let id: Int
    let isCode: Bool
    let text: String
    let language: String
}

private final class MessageChunksBox: NSObject {
    let value: [MessageContentChunk]
    init(_ value: [MessageContentChunk]) { self.value = value }
}

private final class MessageChunkCache {
    static let shared = MessageChunkCache()
    private let cache = NSCache<NSString, MessageChunksBox>()
    
    init() { cache.countLimit = 140 }
    
    func chunks(for content: String) -> [MessageContentChunk] {
        let key = content as NSString
        if let hit = cache.object(forKey: key) { return hit.value }
        let built = MessageChunkCache.split(content)
        cache.setObject(MessageChunksBox(built), forKey: key)
        return built
    }
    
    static func split(_ content: String) -> [MessageContentChunk] {
        var result: [MessageContentChunk] = []
        let pattern = "```(\\w*)\\n?([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [MessageContentChunk(id: 0, isCode: false, text: content, language: "")]
        }
        
        let nsContent = content as NSString
        var lastIndex = 0
        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsContent.length))
        var chunkId = 0
        
        for match in matches {
            let matchRange = match.range
            if matchRange.location > lastIndex {
                let textChunk = nsContent.substring(with: NSRange(location: lastIndex, length: matchRange.location - lastIndex))
                let trimmed = textChunk.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    result.append(MessageContentChunk(id: chunkId, isCode: false, text: textChunk, language: ""))
                    chunkId += 1
                }
            }
            
            let langRange = match.range(at: 1)
            let codeRange = match.range(at: 2)
            let lang = langRange.location != NSNotFound ? nsContent.substring(with: langRange) : ""
            let code = codeRange.location != NSNotFound ? nsContent.substring(with: codeRange).trimmingCharacters(in: .newlines) : ""
            
            result.append(MessageContentChunk(id: chunkId, isCode: true, text: code, language: lang))
            chunkId += 1
            lastIndex = matchRange.location + matchRange.length
        }
        
        if lastIndex < nsContent.length {
            let trailing = nsContent.substring(from: lastIndex)
            if !trailing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(MessageContentChunk(id: chunkId, isCode: false, text: trailing, language: ""))
            }
        }
        
        return result.isEmpty ? [MessageContentChunk(id: 0, isCode: false, text: content, language: "")] : result
    }
}

public struct FormattedMessageContentView: View {
    let content: String
    
    public init(content: String) {
        self.content = content
    }
    
    private var chunks: [MessageContentChunk] {
        MessageChunkCache.shared.chunks(for: content)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(chunks) { chunk in
                if chunk.isCode {
                    CodeBlockView(code: chunk.text, language: chunk.language)
                } else {
                    MarkdownBlocksView(text: chunk.text)
                }
            }
        }
    }
}
