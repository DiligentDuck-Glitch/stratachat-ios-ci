import SwiftUI
import PhotosUI
import PDFKit
import AVFoundation
import UniformTypeIdentifiers

public struct ComposerView: View {
    @ObservedObject var chatVM: ChatViewModel
    @FocusState private var isFocused: Bool
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedVideo: PhotosPickerItem? = nil
    @State private var showPhotosPicker: Bool = false
    @State private var showVideoPicker: Bool = false
    @State private var showCamera: Bool = false
    @State private var cameraImage: UIImage? = nil
    @State private var showFileImporter: Bool = false
    @State private var inputHeight: CGFloat = 34
    
    public init(chatVM: ChatViewModel) {
        self.chatVM = chatVM
    }
    
    private var placeholder: String {
        chatVM.backend == .hermes ? "Message Hermes Agent…" : "Message Strata…"
    }
    
    // These sit outside body so the compiler is not resolving the entire composer as one
    // expression every rebuild.
    @ViewBuilder
    private var slashMenu: some View {
        if chatVM.inputText.starts(with: "/") {
            HStack {
                Spacer(minLength: 20)
                SlashCommandsMenuView(
                    query: chatVM.inputText,
                    onSelect: { cmd in
                        if cmd.isDirectAction {
                            chatVM.inputText = ""
                            switch cmd.name {
                            case "/compact": chatVM.compactChat()
                            case "/retry": chatVM.regenerate()
                            case "/undo": chatVM.undo()
                            case "/clear", "/new": chatVM.newChat()
                            case "/model": chatVM.showModelPicker = true
                            case "/status", "/help": chatVM.showSettings = true
                            case "/stop": chatVM.stop()
                            default: break
                            }
                        } else {
                            chatVM.inputText = cmd.name + " "
                        }
                    },
                    onInsert: { cmd in
                        chatVM.inputText = cmd.name + " "
                    }
                )
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    @ViewBuilder
    private var clipCard: some View {
        if chatVM.attachedClipData != nil {
            HStack(spacing: 10) {
                if let thumb = chatVM.attachedClipThumb {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15), lineWidth: 1))
                } else {
                    Image(systemName: "video.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "7c5cff"))
                        .frame(width: 58, height: 58)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Video clip")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Sent encrypted, read as sampled frames")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.55))
                }
                
                Spacer()
                
                Button {
                    chatVM.attachedClipData = nil
                    chatVM.attachedClipThumb = nil
                    chatVM.attachedClipContainer = "mp4"
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(8)
            .background(Color(hex: "181826"))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }
    
    @ViewBuilder
    private var queueChip: some View {
        if !chatVM.queuedPrompts.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "7c5cff"))
                
                Text("Queued \(chatVM.queuedPrompts.count) · \(chatVM.queuedPrompts.first ?? "")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                
                Spacer()
                
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    chatVM.clearQueue()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(hex: "7c5cff").opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "7c5cff").opacity(0.25), lineWidth: 1))
        }
    }
    
    /// Empty composer gives a plain stop, a filled one interrupts and sends what is typed.
    /// Long press exposes the queue choice.
    @ViewBuilder
    private var actionButton: some View {
        if chatVM.isGenerating {
            let hasDraft = !chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !chatVM.attachedImages.isEmpty
                || chatVM.attachedClipData != nil
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if hasDraft {
                    chatVM.stop()
                    chatVM.send()
                    chatVM.inputText = ""
                } else {
                    chatVM.stop()
                }
            } label: {
                Image(systemName: hasDraft ? "arrow.up" : "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(hasDraft ? Color(hex: "7c5cff") : Color(hex: "ff453a"))
                    .clipShape(Circle())
            }
            .contextMenu {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    chatVM.enqueuePrompt()
                } label: {
                    Label("Queue this message", systemImage: "clock.arrow.circlepath")
                }
                Button {
                    chatVM.stop()
                } label: {
                    Label("Stop without sending", systemImage: "stop.fill")
                }
            }
            .layoutPriority(2)
        } else {
            sendOrVoiceButton
        }
    }
    
    @ViewBuilder
    private var sendOrVoiceButton: some View {
        let canSend = !chatVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !chatVM.attachedImages.isEmpty
            || chatVM.attachedClipData != nil
        let isEditing = chatVM.editingMessage != nil
        if canSend {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                chatVM.send()
                chatVM.inputText = ""
            } label: {
                Image(systemName: isEditing ? "arrow.triangle.branch" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isEditing ? .black : .white)
                    .frame(width: 34, height: 34)
                    .background(isEditing ? Color(hex: "ffd60a") : Color(hex: "7c5cff"))
                    .clipShape(Circle())
            }
            .layoutPriority(2)
        } else {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                chatVM.showVoiceMode = true
            } label: {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "7c5cff"), Color(hex: "a855f7")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
                    .shadow(color: Color(hex: "7c5cff").opacity(0.4), radius: 4)
            }
            .layoutPriority(2)
        }
    }
    
    @ViewBuilder
    private var editingBanner: some View {
        if chatVM.editingMessage != nil {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "ffd60a"))
                
                Text("Editing prompt · Conversation branches from here")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                
                Spacer()
                
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    chatVM.cancelEditing()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(hex: "ffd60a").opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "ffd60a").opacity(0.25), lineWidth: 1))
        }
    }
    
    @ViewBuilder
    private var imageStrip: some View {
        if !chatVM.attachedImages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(chatVM.attachedImages.enumerated()), id: \.offset) { index, img in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15), lineWidth: 1))
                            
                            Button {
                                chatVM.attachedImages.remove(at: index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(4)
                                    .background(Color.black.opacity(0.85))
                                    .clipShape(Circle())
                            }
                            .offset(x: 4, y: -4)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    public var body: some View {
        VStack(spacing: 6) {
            slashMenu
            
            editingBanner
            
            imageStrip
            
            clipCard
            
            queueChip
            
            // Composer pill
            HStack(alignment: .bottom, spacing: 6) {
                // Attach button with Camera, Photos, Files menu
                Menu {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            showCamera = true
                        } else {
                            chatVM.errorMessage = "Camera is not available on this device"
                        }
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showPhotosPicker = true
                    } label: {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }
                    
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showVideoPicker = true
                    } label: {
                        Label("Video", systemImage: "video")
                    }
                    
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showFileImporter = true
                    } label: {
                        Label("Files", systemImage: "folder")
                    }
                    
                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .layoutPriority(2)
                
                // Text input
                AutoSizingTextView(
                    text: $chatVM.inputText,
                    calculatedHeight: $inputHeight,
                    placeholder: placeholder,
                    minHeight: 34,
                    maxHeight: 110
                )
                .frame(maxWidth: .infinity)
                .frame(height: inputHeight)
                .padding(.horizontal, 4)
                
                actionButton
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(hex: "1c1c26"))
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(Color(hex: "09090f"))
        .photosPicker(
            isPresented: $showPhotosPicker,
            selection: $selectedItems,
            maxSelectionCount: 4,
            matching: .images
        )
        .onChange(of: selectedItems) { newItems in
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        chatVM.attachedImages.append(img)
                    }
                }
                selectedItems = []
            }
        }
        .photosPicker(
            isPresented: $showVideoPicker,
            selection: $selectedVideo,
            matching: .videos
        )
        .onChange(of: selectedVideo) { item in
            guard let picked = item else { return }
            Task {
                var clipData: Data? = nil
                var clipURL: URL? = nil
                do {
                    clipData = try await picked.loadTransferable(type: Data.self)
                } catch {
                    do {
                        clipURL = try await picked.loadTransferable(type: URL.self)
                    } catch {
                        clipURL = nil
                    }
                }
                // Decoding the clip and pulling a still out of it run on a background queue so
                // the composer keeps animating while the clip loads.
                let outcome = await Task.detached(priority: .userInitiated) { () -> ClipImport.Outcome in
                    if let clip = clipData { return ClipImport.finish(clip) }
                    if let url = clipURL { return ClipImport.finish(try? Data(contentsOf: url)) }
                    return .failed
                }.value
                await MainActor.run {
                    switch outcome {
                    case .loaded(let clip, let still, let container):
                        chatVM.attachedClipData = clip
                        chatVM.attachedClipThumb = still
                        chatVM.attachedClipContainer = container
                    case .failed:
                        chatVM.errorMessage = "Could not read that clip, or it is over the 25 MB limit"
                    }
                    selectedVideo = nil
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView(selectedImage: $cameraImage)
                .ignoresSafeArea()
        }
        .onChange(of: cameraImage) { newImg in
            if let img = newImg {
                chatVM.attachedImages.append(img)
                cameraImage = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ComposerPasteRequested"))) { _ in
            // A paste the text view cannot handle itself (image, PDF, document) arrives here,
            // so long-press Paste and the keyboard paste button work without the plus menu.
            pasteFromClipboard()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    attachFile(url)
                }
            case .failure(let err):
                chatVM.errorMessage = "Failed to load file: \(err.localizedDescription)"
            }
        }
    }
    
    // MARK: - Attachments from files and clipboard
    
    /// One path for anything imported or pasted: images become attachments, documents and text
    /// become prompt content.
    private func attachFile(_ url: URL) {
        // Pasted file URLs are not always security scoped, so only stop what was started.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        
        let ext = url.pathExtension.lowercased()
        let fileName = url.lastPathComponent
        
        if ["png", "jpg", "jpeg", "webp", "gif", "heic"].contains(ext),
           let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            chatVM.attachedImages.append(img)
            return
        }
        
        if ext == "pdf", let text = pdfText(url) {
            appendFileText(fileName, text)
            return
        }
        
        if ["docx", "doc", "rtf", "txt", "md", "csv", "json", "html", "swift", "py", "js"].contains(ext),
           let text = richText(url) {
            appendFileText(fileName, text)
            return
        }
        
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            appendFileText(fileName, content)
            return
        }
        
        chatVM.errorMessage = "Could not read text from '\(fileName)'"
    }
    
    private func appendFileText(_ fileName: String, _ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            chatVM.errorMessage = "'\(fileName)' has no readable text layer"
            return
        }
        let capped = trimmed.count > 12000
            ? String(trimmed.prefix(12000)) + "\n… truncated"
            : trimmed
        let header = "--- File: \(fileName) ---\n"
        if chatVM.inputText.isEmpty {
            chatVM.inputText = "\(header)\(capped)\n"
        } else {
            chatVM.inputText += "\n\n\(header)\(capped)\n"
        }
    }
    
    private func pdfText(_ url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        var text = ""
        for index in 0..<document.pageCount {
            text += (document.page(at: index)?.string ?? "") + "\n"
        }
        return text
    }
    
    private func richText(_ url: URL) -> String? {
        guard let attributed = try? NSAttributedString(
            url: url,
            options: [:],
            documentAttributes: nil
        ) else {
            return nil
        }
        return attributed.string
    }
    
    private func pasteFromClipboard() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let pasteboard = UIPasteboard.general
        let room = max(0, 8 - chatVM.attachedImages.count)
        
        if room > 0, let images = pasteboard.images, !images.isEmpty {
            chatVM.attachedImages.append(contentsOf: images.prefix(room))
            return
        }
        
        if let url = pasteboard.urls?.first {
            attachFile(url)
            return
        }
        
        if let string = pasteboard.string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if chatVM.inputText.isEmpty {
                chatVM.inputText = string
            } else {
                chatVM.inputText += "\n" + string
            }
            return
        }
        
        chatVM.errorMessage = "Nothing usable on the clipboard"
    }
}
