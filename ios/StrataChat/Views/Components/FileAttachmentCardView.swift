import SwiftUI
import QuickLook

public struct FileAttachmentCardView: View {
    public let file: GeneratedFileInfo
    @State private var showQuickLook: Bool = false
    @State private var showShareSheet: Bool = false
    
    public init(file: GeneratedFileInfo) {
        self.file = file
    }
    
    private var isPDF: Bool {
        file.fileType.lowercased() == "pdf"
    }
    
    private var badgeColor: Color {
        isPDF ? Color(hex: "ff453a") : Color(hex: "007aff")
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // File icon badge
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(badgeColor.opacity(0.18))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(badgeColor.opacity(0.4), lineWidth: 1)
                        )
                    
                    VStack(spacing: 2) {
                        Image(systemName: isPDF ? "doc.fill" : "doc.text.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(badgeColor)
                        Text(isPDF ? "PDF" : "DOCX")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundColor(badgeColor)
                    }
                }
                
                // Filename & Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.filename)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(file.sizeFormatted)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(hex: "34d399"))
                        Text("•")
                            .foregroundColor(.white.opacity(0.3))
                        Text(file.fileTypeDisplay)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
            }
            
            // Action Buttons
            HStack(spacing: 8) {
                // QuickLook Preview button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showQuickLook = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 11))
                        Text("Preview")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                // Share / AirDrop button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showShareSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .bold))
                        Text("Share / AirDrop")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(Color(hex: "00f2fe"))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "151522"))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(badgeColor.opacity(0.3), lineWidth: 1)
                )
        )
        .quickLookPreview($showQuickLook, url: file.fileURL)
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(activityItems: [file.fileURL])
        }
    }
}

// MARK: - Native iOS QuickLook Wrapper
private struct QuickLookPreviewModifier: ViewModifier {
    @Binding var isPresented: Bool
    let url: URL
    
    func body(content: Content) -> some View {
        content
            .background(
                QuickLookControllerRepresentable(isPresented: $isPresented, url: url)
                    .frame(width: 0, height: 0)
            )
    }
}

private extension View {
    func quickLookPreview(_ isPresented: Binding<Bool>, url: URL) -> some View {
        self.modifier(QuickLookPreviewModifier(isPresented: isPresented, url: url))
    }
}

private struct QuickLookControllerRepresentable: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let url: URL
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented && context.coordinator.controller == nil {
            let ql = QLPreviewController()
            ql.dataSource = context.coordinator
            ql.delegate = context.coordinator
            context.coordinator.controller = ql
            uiViewController.present(ql, animated: true)
        } else if !isPresented && context.coordinator.controller != nil {
            context.coordinator.controller?.dismiss(animated: true) {
                context.coordinator.controller = nil
            }
        }
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var parent: QuickLookControllerRepresentable
        var controller: QLPreviewController?
        
        init(_ parent: QuickLookControllerRepresentable) {
            self.parent = parent
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            parent.url as QLPreviewItem
        }
        
        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            parent.isPresented = false
            self.controller = nil
        }
    }
}

// MARK: - UIActivityViewController Wrapper for Sharing & AirDrop
private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
