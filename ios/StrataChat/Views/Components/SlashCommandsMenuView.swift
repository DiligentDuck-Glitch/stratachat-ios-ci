import SwiftUI

public struct SlashCommandItem: Identifiable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let icon: String
    public let isDirectAction: Bool
    
    public init(name: String, description: String, icon: String, isDirectAction: Bool = false) {
        self.name = name
        self.description = description
        self.icon = icon
        self.isDirectAction = isDirectAction
    }
}

public struct SlashCommandsMenuView: View {
    let query: String
    let onSelect: (SlashCommandItem) -> Void
    let onInsert: (SlashCommandItem) -> Void
    
    private let allCommands: [SlashCommandItem] = [
        SlashCommandItem(name: "/help", description: "Show available commands", icon: "questionmark.circle.fill", isDirectAction: true),
        SlashCommandItem(name: "/new", description: "Start a new session", icon: "plus.circle.fill", isDirectAction: true),
        SlashCommandItem(name: "/stop", description: "Kill running background job", icon: "stop.circle.fill", isDirectAction: true),
        SlashCommandItem(name: "/status", description: "Show session, model & GPU info", icon: "gauge.with.needle.fill", isDirectAction: true),
        SlashCommandItem(name: "/compact", description: "Summarize earlier turns to free up context", icon: "arrow.down.right.and.arrow.up.left", isDirectAction: true),
        SlashCommandItem(name: "/retry", description: "Regenerate latest assistant response", icon: "arrow.clockwise", isDirectAction: true),
        SlashCommandItem(name: "/undo", description: "Delete last turn and revert", icon: "arrow.uturn.backward", isDirectAction: true),
        SlashCommandItem(name: "/model", description: "Switch between Swift 1.5, Original & Hermes", icon: "cpu", isDirectAction: true),
        SlashCommandItem(name: "/clear", description: "Clear conversation history & start fresh", icon: "trash.fill", isDirectAction: true)
    ]
    
    private var filteredCommands: [SlashCommandItem] {
        let clean = query.lowercased().trimmingCharacters(in: .whitespaces)
        if clean.isEmpty || clean == "/" {
            return allCommands
        }
        return allCommands.filter { $0.name.lowercased().contains(clean) }
    }
    
    public init(query: String, onSelect: @escaping (SlashCommandItem) -> Void, onInsert: ((SlashCommandItem) -> Void)? = nil) {
        self.query = query
        self.onSelect = onSelect
        self.onInsert = onInsert ?? onSelect
    }
    
    public var body: some View {
        if !filteredCommands.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredCommands) { cmd in
                            HStack(spacing: 0) {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onSelect(cmd)
                                } label: {
                                    HStack(spacing: 10) {
                                        // Circular avatar badge (Telegram Agent badge)
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: [Color(hex: "d870ff"), Color(hex: "8a4bff")],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 30, height: 30)
                                            
                                            Text("A")
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                        }
                                        
                                        // Command name & description inline
                                        HStack(spacing: 6) {
                                            Text(cmd.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                            
                                            Text(cmd.description)
                                                .font(.system(size: 13))
                                                .foregroundColor(.white.opacity(0.48))
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                        }
                                        
                                        Spacer(minLength: 4)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(SlashCommandRowButtonStyle())
                                
                                // Trailing arrow button (Telegram diagonal down-left arrow to fill input)
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onInsert(cmd)
                                } label: {
                                    Image(systemName: "arrow.down.left")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white.opacity(0.38))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(SlashCommandRowButtonStyle())
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: min(CGFloat(filteredCommands.count) * 44 + 12, 220))
            }
            .frame(width: 295)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: "181822").opacity(0.85))
                    .background(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.45), radius: 14, x: 0, y: -4)
        }
    }
}

private struct SlashCommandRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
