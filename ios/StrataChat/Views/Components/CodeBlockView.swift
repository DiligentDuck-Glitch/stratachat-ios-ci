import SwiftUI

public struct CodeBlockView: View {
    let code: String
    let language: String
    
    @State private var copied: Bool = false
    
    public init(code: String, language: String = "") {
        self.code = code
        self.language = language.isEmpty ? "code" : language
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "7c5cff"))
                    
                    Text(language.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                Button {
                    UIPasteboard.general.string = code
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copied ? "Copied" : "Copy Code")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(copied ? Color.green : .white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(hex: "1e1f2f"))
            
            // Code content with horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(hex: "e2e8f0"))
                    .lineSpacing(3)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(hex: "0d0e17"))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .padding(.vertical, 4)
    }
}
