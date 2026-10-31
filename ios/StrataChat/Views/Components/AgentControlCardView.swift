import SwiftUI

public struct AgentControlCardView: View {
    let approval: ApprovalPrompt?
    let clarify: ClarifyPrompt?
    let onApproval: (String, String) -> Void
    let onClarify: (String, String) -> Void
    
    public init(
        approval: ApprovalPrompt? = nil,
        clarify: ClarifyPrompt? = nil,
        onApproval: @escaping (String, String) -> Void = { _, _ in },
        onClarify: @escaping (String, String) -> Void = { _, _ in }
    ) {
        self.approval = approval
        self.clarify = clarify
        self.onApproval = onApproval
        self.onClarify = onClarify
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let a = approval {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 16))
                    Text("Action Permission Request")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                
                if let reason = a.reason {
                    Text(reason)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                }
                
                if let cmd = a.command {
                    Text(cmd)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Color(hex: "ffd60a"))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                if let res = a.resolved {
                    Text("Resolved: \(res)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                } else {
                    HStack(spacing: 8) {
                        Button("Run") {
                            onApproval(a.id, "once")
                        }
                        .buttonStyle(ActionBtnStyle(color: Color(hex: "7c5cff")))
                        
                        Button("Always Allow") {
                            onApproval(a.id, "always")
                        }
                        .buttonStyle(ActionBtnStyle(color: Color(hex: "30d158")))
                        
                        Button("Reject") {
                            onApproval(a.id, "deny")
                        }
                        .buttonStyle(ActionBtnStyle(color: Color(hex: "ff453a")))
                    }
                }
            }
            
            if let c = clarify {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(Color(hex: "22d3ee"))
                        .font(.system(size: 16))
                    Text("Clarification Needed")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text(c.question)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                
                if let res = c.resolved {
                    Text("Answered: \(res)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                } else if let choices = c.choices {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(choices, id: \.self) { choice in
                            Button {
                                onClarify(c.id, choice)
                            } label: {
                                Text(choice)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(hex: "181826"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

struct ActionBtnStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(configuration.isPressed ? 0.6 : 0.9))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
