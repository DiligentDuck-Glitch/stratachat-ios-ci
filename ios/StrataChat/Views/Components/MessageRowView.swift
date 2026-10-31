import SwiftUI

// Typing in the composer, a stream publish and the 12s transcript refresh all republish the
// whole message list. Deciding equality on the message alone lets unchanged rows skip their
// body, which is what stops every keystroke from re-rendering the entire transcript.
public struct MessageRowView: View, Equatable {
    let message: ChatMessage
    let onApproval: (String, String) -> Void
    let onClarify: (String, String) -> Void
    let onRegenerate: () -> Void
    let onEdit: (ChatMessage) -> Void
    let onPerformance: (ChatMessage) -> Void
    
    public static func == (lhs: MessageRowView, rhs: MessageRowView) -> Bool {
        lhs.message == rhs.message
    }
    
    @State private var thinkingExpanded: Bool = false
    @State private var userToggledThinking: Bool = false
    @State private var copied: Bool = false
    
    private var isThinkingExpanded: Bool {
        if userToggledThinking {
            return thinkingExpanded
        }
        return (message.status == "streaming" || message.status == "generating") && message.content.isEmpty
    }
    
    public init(
        message: ChatMessage,
        onApproval: @escaping (String, String) -> Void = { _, _ in },
        onClarify: @escaping (String, String) -> Void = { _, _ in },
        onRegenerate: @escaping () -> Void = {},
        onEdit: @escaping (ChatMessage) -> Void = { _ in },
        onPerformance: @escaping (ChatMessage) -> Void = { _ in }
    ) {
        self.message = message
        self.onApproval = onApproval
        self.onClarify = onClarify
        self.onRegenerate = onRegenerate
        self.onEdit = onEdit
        self.onPerformance = onPerformance
    }
    
    // Replay of an interleaved turn: reasoning folds and answer blocks in the order they ran.
    // The first reasoning block opens itself so the pattern is obvious without a tap.
    @ViewBuilder
    private func segmentView(_ segment: MessageSegment) -> some View {
        if segment.kind == "reasoning" {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        thinkingExpanded.toggle()
                        userToggledThinking = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "ffd60a"))
                        Text("Thoughts")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                        Image(systemName: thinkingExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                if thinkingExpanded {
                    Text(segment.text)
                        .font(.system(size: 13.5))
                        .foregroundColor(.white.opacity(0.75))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                }
            }
        } else {
            FormattedMessageContentView(content: segment.text)
        }
    }

    public var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
            if message.isUser {
                // User Bubble
                VStack(alignment: .trailing, spacing: 4) {
                    if let imgs = message.images, !imgs.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(imgs, id: \.self) { imgData in
                                if let data = Data(base64Encoded: imgData.replacingOccurrences(of: "data:image/jpeg;base64,", with: "")),
                                   let uiImg = UIImage(data: data) {
                                    Image(uiImage: uiImg)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                    
                    HStack(alignment: .bottom, spacing: 6) {
                        Button {
                            onEdit(message)
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.35))
                                .frame(width: 24, height: 24)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())
                        }
                        
                        if !message.content.isEmpty {
                            Text(message.content)
                                .font(.system(size: 15.5))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color(hex: "2a2847"))
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12), lineWidth: 1))
                        }
                    }
                    .contextMenu {
                        Button {
                            onEdit(message)
                        } label: {
                            Label("Edit Prompt", systemImage: "pencil")
                        }
                        
                        Button {
                            UIPasteboard.general.string = message.content
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Label("Copy Text", systemImage: "doc.on.doc")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 30)
            } else {
                // Assistant Message
                VStack(alignment: .leading, spacing: 8) {
                    // Tool calls
                    if let tools = message.toolCalls, !tools.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(tools) { tool in
                                    HStack(spacing: 5) {
                                        if tool.status == "running" {
                                            ProgressView()
                                                .scaleEffect(0.6)
                                        } else if tool.status == "error" {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.red)
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.green)
                                        }
                                        Text(tool.name)
                                            .font(.system(size: 11, design: .monospaced))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                                }
                            }
                        }
                    }
                    
                    // A thinking model that answers, then thinks again, then answers produced one
                    // collapsed Thoughts block followed by the whole answer, so the tail of the
                    // reasoning rendered above the text it belonged to. When the backend recorded
                    // the turn as ordered segments, replay them in the order they actually happened.
                    let ordered = message.meta?.segments ?? []
                    let segmentKinds = Set(ordered.map { $0.kind })
                    let usesSegments = ordered.count >= 3 && segmentKinds.contains("reasoning") && segmentKinds.contains("content")
                    if usesSegments {
                        ForEach(Array(ordered.enumerated()), id: \.offset) { _, segment in
                            segmentView(segment)
                        }
                    } else {
                    // Thinking block
                    if let th = message.thinking, !th.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    thinkingExpanded = !isThinkingExpanded
                                    userToggledThinking = true
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(hex: "ffd60a"))
                                    
                                    if let ts = message.meta?.thoughtS {
                                        Text("Thoughts (\(String(format: "%.1f", ts))s)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.75))
                                    } else if (message.status == "streaming" || message.status == "generating") && message.content.isEmpty {
                                        Text("Thinking…")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(Color(hex: "ffd60a"))
                                    } else {
                                        Text("Thoughts")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.75))
                                    }
                                    
                                    Image(systemName: isThinkingExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                            }
                            
                            if isThinkingExpanded {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(th)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.7))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    if (message.status == "streaming" || message.status == "generating") && message.content.isEmpty {
                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(Color(hex: "ffd60a"))
                                                .frame(width: 5, height: 5)
                                            Text("Thinking live…")
                                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                                .foregroundColor(Color(hex: "ffd60a").opacity(0.8))
                                        }
                                        .padding(.top, 2)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(hex: "ffd60a").opacity(0.18), lineWidth: 1)
                                )
                            }
                        }
                    }
                    }

                    // Main content. Skipped in segment mode: each content block already rendered
                    // in order, and `message.content` is those blocks concatenated.
                    if !usesSegments && !message.content.isEmpty {
                        FormattedMessageContentView(content: message.content)
                    } else if message.status == "streaming" || message.status == "generating" {
                        PrefillProgressView(message: message)
                            .padding(.vertical, 6)
                    }
                    
                    // Generated file attachments (PDF / Word .docx)
                    if let files = message.generatedFiles, !files.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(files) { file in
                                FileAttachmentCardView(file: file)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Error display
                    if let err = message.error {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        }
                    }
                    
                    // Agent control card
                    if message.approvalPrompt != nil || message.clarifyPrompt != nil {
                        AgentControlCardView(
                            approval: message.approvalPrompt,
                            clarify: message.clarifyPrompt,
                            onApproval: onApproval,
                            onClarify: onClarify
                        )
                    }
                    
                    // Claude Action Toolbar
                    if message.status != "streaming" || !message.content.isEmpty || !(message.thinking ?? "").isEmpty {
                        ClaudeActionToolbar(message: message, onRegenerate: onRegenerate,
                                            onPerformance: onPerformance)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 20)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}
