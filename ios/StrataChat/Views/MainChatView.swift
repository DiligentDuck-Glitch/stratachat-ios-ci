import SwiftUI

private struct ScrollBottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

public struct MainChatView: View {
    @StateObject private var chatVM = ChatViewModel()
    @StateObject private var statusVM = StatusViewModel()
    @ObservedObject private var voiceEngine = VoiceEngine.shared
    @State private var showScrollToBottom: Bool = false
    @State private var userScrolledUp: Bool = false
    @State private var keyboardSettle: DispatchWorkItem?
    
    private let suggestions = [
        "Explain how speculative decoding works",
        "Write a bash one-liner to find the 10 largest files",
        "Compare Swift 1.5 vs Original GSQ reasoning"
    ]
    
    public init() {}
    
    private func settleTranscript(_ proxy: ScrollViewProxy, delay: TimeInterval) {
        // Opening and closing the keyboard used to fire two animated scrolls a beat apart, which
        // looked like stutter in the transcript while a reply was still arriving. One settle per
        // event, replacing any pending one.
        //
        // Only settles while following. Settling on a keyboard event also yanked the transcript to the
        // bottom mid-read, which is the visible half of the snap-back complaint.
        keyboardSettle?.cancel()
        guard !userScrolledUp else { return }
        let work = DispatchWorkItem {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                proxy.scrollTo("bottomAnchor", anchor: .bottom)
            }
        }
        keyboardSettle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    
    private func hideKeyboard() {
        // Resigning through UIKit alone leaves the scroll layout sitting at the keyboard inset until
        // the user drags, so the composer text view is asked to resign as well.
        NotificationCenter.default.post(name: NSNotification.Name("ComposerDidBlur"), object: nil)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private var isAnySheetPresented: Bool {
        chatVM.showLocalModelManager || chatVM.showModelPicker || chatVM.showSettings || chatVM.showVoiceMode || chatVM.showContextSheet || chatVM.showPerformanceSheet
    }

    // A drawer drag has to begin inside the left edge strip and below the Dynamic Island.
    // `closeDrawer` opens the drawer from the top-left, so the top-left corner stays live.
    private static func dragOpensDrawer(_ location: CGPoint) -> Bool {
        let screenWidth = UIApplication.shared.windows.first?.screen.bounds.width ?? 390
        let edgeWidth = min(80, screenWidth * 0.22)
        return location.y > 90
            && location.x < edgeWidth
            && location.x < screenWidth * 0.60
    }
    
    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Floating Top Bar
                TopBarView(chatVM: chatVM, statusVM: statusVM)
                    .zIndex(10)
                
                miniVoiceBar
                    .zIndex(9)
                
                // Wake-on-LAN progress banner
                if chatVM.isWakingPC, let wakingStatus = chatVM.wakingStatus {
                    HStack(spacing: 10) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "7c5cff")))
                            .scaleEffect(0.85)
                        Text(wakingStatus)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(hex: "7c5cff").opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "7c5cff").opacity(0.4), lineWidth: 1))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Error banner if any error occurred
                if let err = chatVM.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(err)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                chatVM.errorMessage = nil
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.white.opacity(0.6))
                                .font(.system(size: 12))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.3), lineWidth: 1))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onEnded { value in
                                if value.translation.height < -12 {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        chatVM.errorMessage = nil
                                    }
                                }
                            }
                    )
                }
                
                // Messages Scroller
                ScrollViewReader { proxy in
                    GeometryReader { scrollGeo in
                        ZStack(alignment: .bottomTrailing) {
                            ScrollView {
                                VStack(spacing: 16) {
                                    if chatVM.messages.isEmpty {
                                        // Empty state
                                        VStack(spacing: 12) {
                                            Spacer(minLength: 60)
                                            
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 44))
                                                .foregroundColor(Color(hex: "7c5cff"))
                                                .padding(18)
                                                .background(Color(hex: "7c5cff").opacity(0.12))
                                                .clipShape(Circle())
                                                .shadow(color: Color(hex: "7c5cff").opacity(0.4), radius: 20)
                                            
                                            Text(chatVM.backend == .hermes ? "Hermes Agent" : "What can I help with?")
                                                .font(.system(size: 22, weight: .bold))
                                                .foregroundColor(.white)
                                            
                                            Text(chatVM.backend == .hermes ? "Autonomous agent with tools, permissions & memory." : "Direct 262k context streaming from your RTX 5070 Ti.")
                                                .font(.system(size: 13))
                                                .foregroundColor(.white.opacity(0.5))
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal, 32)
                                            
                                            VStack(spacing: 8) {
                                                ForEach(suggestions, id: \.self) { sug in
                                                    Button {
                                                        hideKeyboard()
                                                        chatVM.send(text: sug)
                                                    } label: {
                                                        Text(sug)
                                                            .font(.system(size: 13.5))
                                                            .foregroundColor(.white.opacity(0.85))
                                                            .frame(maxWidth: .infinity, alignment: .leading)
                                                            .padding(.horizontal, 14)
                                                            .padding(.vertical, 11)
                                                            .background(Color(hex: "181826"))
                                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 20)
                                            .padding(.top, 10)
                                            
                                            Spacer(minLength: 40)
                                        }
                                    } else {
                                        ForEach(chatVM.messages) { msg in
                                            MessageRowView(
                                                message: msg,
                                                onApproval: { promptId, choice in
                                                    chatVM.respondApproval(promptId: promptId, choice: choice)
                                                },
                                                onClarify: { promptId, answer in
                                                    chatVM.respondClarify(promptId: promptId, answer: answer)
                                                },
                                                onRegenerate: {
                                                    chatVM.regenerate()
                                                },
                                                onEdit: { editedMsg in
                                                    chatVM.startEditing(message: editedMsg)
                                                },
                                                onPerformance: { picked in
                                                    chatVM.performanceMessage = picked
                                                    chatVM.showPerformanceSheet = true
                                                }
                                            )
                                            .equatable()
                                            .id(msg.id)
                                        }
                                        
                                        Color.clear
                                            .frame(height: 1)
                                            .id("bottomAnchor")
                                            .background(
                                                GeometryReader { geo in
                                                    Color.clear.preference(
                                                        key: ScrollBottomOffsetKey.self,
                                                        value: geo.frame(in: .named("chatScrollSpace")).maxY
                                                    )
                                                }
                                            )
                                    }
                                }
                                .padding(.top, 8)
                                .padding(.bottom, 14)
                            }
                            .coordinateSpace(name: "chatScrollSpace")
                            .scrollBounceBehavior(.basedOnSize)
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    hideKeyboard()
                                }
                            )
                            .scrollDismissesKeyboard(.immediately)
                            .refreshable {
                                await chatVM.refreshCurrentChat()
                            }
                            .onAppear {
                                chatVM.startLiveChatRefresh()
                                chatVM.startHardwarePolling()
                            }
                            .onDisappear {
                                chatVM.stopLiveChatRefresh()
                                chatVM.stopHardwarePolling()
                            }
                            .onPreferenceChange(ScrollBottomOffsetKey.self) { bottomY in
                                guard !chatVM.messages.isEmpty else {
                                    if showScrollToBottom {
                                        showScrollToBottom = false
                                    }
                                    userScrolledUp = false
                                    return
                                }
                                let viewportH = scrollGeo.size.height
                                let isScrolledAway = bottomY > (viewportH + 70)
                                let isAtBottom = bottomY <= (viewportH + 16)

                                if isScrolledAway && !showScrollToBottom {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showScrollToBottom = true
                                    }
                                    userScrolledUp = true
                                } else if isAtBottom && showScrollToBottom {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showScrollToBottom = false
                                    }
                                    userScrolledUp = false
                                }
                            }
                            .onChange(of: chatVM.messages.count) { _ in
                                // This was the snap-back. A new message row - the streaming assistant
                                // bubble, a user send, or the 12s transcript refresh - reset the follow
                                // state and dragged the view to the bottom even when the reader was holding
                                // a position mid-page. Following is now decided only by scroll position and
                                // by the jump-to-bottom button, never by content arriving.
                                guard !userScrolledUp else { return }
                                withAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo("bottomAnchor", anchor: .bottom)
                                }
                            }
                            .onChange(of: chatVM.messages.last?.role) { newRole in
                                // Sending a message re-engages following. Without this a reader who had
                                // scrolled up would never see the message they just sent.
                                guard newRole == "user" else { return }
                                userScrolledUp = false
                                withAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo("bottomAnchor", anchor: .bottom)
                                }
                            }
                            .onChange(of: chatVM.messages.last?.content) { _ in
                                guard chatVM.isGenerating && !userScrolledUp else { return }
                                proxy.scrollTo("bottomAnchor", anchor: .bottom)
                            }
                            .onChange(of: chatVM.messages.last?.thinking) { _ in
                                guard chatVM.isGenerating && !userScrolledUp else { return }
                                proxy.scrollTo("bottomAnchor", anchor: .bottom)
                            }
                            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                                settleTranscript(proxy, delay: 0.12)
                            }
                            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ComposerDidFocus"))) { _ in
                                // Tapping into the composer is not a request to jump back to the bottom of
                                // a transcript the user is reading.
                            }
                            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ComposerDidBlur"))) { _ in
                                // Without this the transcript keeps the keyboard inset after a tap
                                // dismiss, so the text looks stuck above the composer until a drag.
                                settleTranscript(proxy, delay: 0.18)
                            }
                            
                            // Scroll to bottom button
                            if showScrollToBottom {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    userScrolledUp = false
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        proxy.scrollTo("bottomAnchor", anchor: .bottom)
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                            proxy.scrollTo("bottomAnchor", anchor: .bottom)
                                        }
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                                            proxy.scrollTo("bottomAnchor", anchor: .bottom)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 36, height: 36)
                                        .background(Color(hex: "222234"))
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                                        .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
                                }
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                                .padding(.trailing, 18)
                                .padding(.bottom, 12)
                            }
                        }
                    }
                }
                .onChange(of: chatVM.showDrawer) { isShown in
                    if isShown {
                        hideKeyboard()
                    }
                }
                
                // Bottom Composer Dock
                ComposerView(chatVM: chatVM)
                    .onChange(of: chatVM.isGenerating) { generating in
                        if !generating {
                            chatVM.drainQueue()
                        }
                    }
            }
            
            // Drawer sidebar
            HistoryDrawerView(chatVM: chatVM)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .onChanged { value in
                    guard !chatVM.showDrawer && !isAnySheetPresented else { return }
                    // Only a drag that starts on the left edge strip can open the drawer. Without
                    // this the gesture recognised drags made inside the composer and inside table
                    // scrolls, so selecting text or panning a table opened the drawer instead.
                    guard Self.dragOpensDrawer(value.startLocation) else { return }

                    let horizontal = value.translation.width
                    let vertical = abs(value.translation.height)

                    if !chatVM.isDraggingDrawer {
                        guard horizontal > 16 && horizontal > vertical * 1.4 else { return }
                        hideKeyboard()
                        chatVM.isDraggingDrawer = true
                    }
                    
                    chatVM.drawerDragOffset = max(0, horizontal)
                }
                .onEnded { value in
                    guard chatVM.isDraggingDrawer else { return }
                    let velocity = value.predictedEndTranslation.width - value.translation.width
                    if chatVM.drawerDragOffset > 80 || velocity > 250 {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            chatVM.showDrawer = true
                            chatVM.drawerDragOffset = 0
                            chatVM.isDraggingDrawer = false
                        }
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            chatVM.showDrawer = false
                            chatVM.drawerDragOffset = 0
                            chatVM.isDraggingDrawer = false
                        }
                    }
                }
        )
        .background(Color(hex: "09090f").ignoresSafeArea())
        .sheet(isPresented: $chatVM.showModelPicker) {
            HardwareSheetView(chatVM: chatVM, statusVM: statusVM)
        }
        .sheet(isPresented: $chatVM.showLocalModelManager) {
            LocalModelManagerView()
        }
        .sheet(isPresented: $chatVM.showSettings) {
            SettingsView(statusVM: statusVM)
        }
        .fullScreenCover(isPresented: $chatVM.showVoiceMode) {
            VoiceModeView(chatVM: chatVM)
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Mini Voice Floating Pill (when Voice is running in background)
    @ViewBuilder
    private var miniVoiceBar: some View {
        if voiceEngine.state != .idle && !chatVM.showVoiceMode {
            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    chatVM.showVoiceMode = true
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(miniVoiceOrbColor)
                            .frame(width: 9, height: 9)
                            .shadow(color: miniVoiceOrbColor.opacity(0.8), radius: 4)
                        
                        Text(miniVoiceStatusText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Image(systemName: "chevron.up.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                // Mute toggle
                Button {
                    voiceEngine.toggleMute()
                } label: {
                    Image(systemName: voiceEngine.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 12))
                        .foregroundColor(voiceEngine.isMuted ? Color(hex: "ff453a") : .white)
                        .padding(6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                
                // End session
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    voiceEngine.stopSession()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color(hex: "ff453a"))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(miniVoiceOrbColor.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    private var miniVoiceOrbColor: Color {
        switch voiceEngine.state {
        case .listening:
            return Color(hex: "a855f7")
        case .thinking:
            return Color(hex: "f59e0b")
        case .speaking:
            return Color(hex: "10b981")
        case .idle:
            return Color.gray
        }
    }
    
    private var miniVoiceStatusText: String {
        switch voiceEngine.state {
        case .listening:
            return voiceEngine.isMuted ? "Muted" : "Voice Active · Listening…"
        case .thinking:
            return "Voice Active · Thinking…"
        case .speaking:
            return "Voice Active · Speaking…"
        case .idle:
            return "Voice Connected"
        }
    }
}
