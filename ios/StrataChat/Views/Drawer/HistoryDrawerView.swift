import SwiftUI

public struct HistoryDrawerView: View {
    @ObservedObject var chatVM: ChatViewModel
    @State private var searchText: String = ""
    @State private var renameChatId: String? = nil
    @State private var renameText: String = ""
    @State private var showRenameAlert: Bool = false
    @State private var selectedBackendTab: String = "strata"
    
    public init(chatVM: ChatViewModel) {
        self.chatVM = chatVM
    }
    
    private var filteredChats: [ChatSummary] {
        let backendFiltered = chatVM.chats.filter { chat in
            if selectedBackendTab == "local" {
                return chat.backend == "local"
            } else if selectedBackendTab == "hermes" {
                return chat.backend == "hermes"
            } else {
                return chat.backend != "hermes" && chat.backend != "local"
            }
        }
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return backendFiltered
        }
        return backendFiltered.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.preview?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    private func syncSelectedTab() {
        if chatVM.backend == .local {
            selectedBackendTab = "local"
        } else if chatVM.backend == .hermes {
            selectedBackendTab = "hermes"
        } else {
            selectedBackendTab = "strata"
        }
    }
    
    private func group(for timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()), date >= weekAgo {
            return "Previous 7 Days"
        }
        return "Older"
    }
    
    private var groupedChats: [(String, [ChatSummary])] {
        let sectionOrder = ["Today", "Yesterday", "Previous 7 Days", "Older"]
        var dict: [String: [ChatSummary]] = [:]
        for chat in filteredChats {
            let grp = group(for: chat.updatedAt)
            dict[grp, default: []].append(chat)
        }
        return sectionOrder.compactMap { section in
            guard let items = dict[section], !items.isEmpty else { return nil }
            return (section, items)
        }
    }
    
    public var body: some View {
        GeometryReader { geo in
            let drawerWidth = min(geo.size.width * 0.82, 320)
            let baseOffset: CGFloat = chatVM.showDrawer ? 0 : -drawerWidth
            let currentOffset = baseOffset + chatVM.drawerDragOffset
            let clampedOffset = min(0, max(-drawerWidth, currentOffset))
            let progress = max(0.0, min(1.0, (clampedOffset + drawerWidth) / drawerWidth))
            
            ZStack(alignment: .leading) {
                // Dimmed backdrop that fades in/out with 1:1 progress
                Color.black.opacity(Double(progress) * 0.55)
                    .ignoresSafeArea()
                    .allowsHitTesting(progress > 0.05)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            chatVM.showDrawer = false
                            chatVM.drawerDragOffset = 0
                            chatVM.isDraggingDrawer = false
                        }
                    }
                
                // Drawer panel that tracks finger 1:1
                VStack(alignment: .leading, spacing: 14) {
                        // Header
                        HStack {
                            Text("Conversations")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    chatVM.showDrawer = false
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .padding(8)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 50)
                        
                        // Search bar
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.4))
                            TextField("Search history…", text: $searchText)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        
                        // Strata / Hermes / Local Tab Selector
                        HStack(spacing: 6) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    selectedBackendTab = "strata"
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 10))
                                    Text("Strata")
                                        .font(.system(size: 12, weight: .bold))
                                    let strataCount = chatVM.chats.filter { $0.backend != "hermes" && $0.backend != "local" }.count
                                    Text("\(strataCount)")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(selectedBackendTab == "strata" ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
                                        .clipShape(Capsule())
                                }
                                .foregroundColor(selectedBackendTab == "strata" ? .white : .white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(selectedBackendTab == "strata" ? Color(hex: "7c5cff") : Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    selectedBackendTab = "hermes"
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 10))
                                    Text("Hermes")
                                        .font(.system(size: 12, weight: .bold))
                                    let hermesCount = chatVM.chats.filter { $0.backend == "hermes" }.count
                                    Text("\(hermesCount)")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(selectedBackendTab == "hermes" ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
                                        .clipShape(Capsule())
                                }
                                .foregroundColor(selectedBackendTab == "hermes" ? .white : .white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(selectedBackendTab == "hermes" ? Color(hex: "7c5cff") : Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    selectedBackendTab = "local"
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "cpu.fill")
                                        .font(.system(size: 10))
                                    Text("Local")
                                        .font(.system(size: 12, weight: .bold))
                                    let localCount = chatVM.chats.filter { $0.backend == "local" }.count
                                    Text("\(localCount)")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(selectedBackendTab == "local" ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
                                        .clipShape(Capsule())
                                }
                                .foregroundColor(selectedBackendTab == "local" ? .white : .white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(selectedBackendTab == "local" ? Color(hex: "00f2fe") : Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.horizontal, 14)
                        
                        // New Chat Button for the currently selected section
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            let targetBackend = Backend(rawValue: selectedBackendTab) ?? .strata
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                chatVM.showDrawer = false
                                chatVM.drawerDragOffset = 0
                                chatVM.isDraggingDrawer = false
                            }
                            chatVM.newChat(backend: targetBackend)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text(selectedBackendTab == "local" ? "New On-Device Chat" : (selectedBackendTab == "hermes" ? "New Hermes Agent Chat" : "New Strata Chat (262k)"))
                                    .font(.system(size: 13, weight: .bold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .opacity(0.6)
                            }
                            .foregroundColor(selectedBackendTab == "local" ? .black : .white)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(selectedBackendTab == "local" ? Color(hex: "00f2fe") : Color(hex: "7c5cff"))
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                        }
                        .padding(.horizontal, 14)
                        
                        // Chat list grouped by date
                        List {
                            ForEach(groupedChats, id: \.0) { section, items in
                                Section(header: 
                                    Text(section)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white.opacity(0.4))
                                        .padding(.vertical, 4)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                ) {
                                    ForEach(items) { chat in
                                        Button {
                                            chatVM.selectChat(id: chat.id, title: chat.title, backend: chat.backend)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack(spacing: 6) {
                                                    Text(chat.title)
                                                        .font(.system(size: 14, weight: chat.id == chatVM.currentChatId ? .bold : .medium))
                                                        .foregroundColor(chat.id == chatVM.currentChatId ? Color(hex: "7c5cff") : .white)
                                                        .lineLimit(1)
                                                    
                                                    Spacer(minLength: 4)
                                                    
                                                    if let turns = chat.messageCount, turns > 0 {
                                                        Text("\(turns)")
                                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                                            .foregroundColor(.white.opacity(0.45))
                                                            .padding(.horizontal, 5)
                                                            .padding(.vertical, 2)
                                                            .background(Color.white.opacity(0.06))
                                                            .clipShape(Capsule())
                                                    }
                                                    
                                                    if chat.backend == "local" {
                                                        HStack(spacing: 3) {
                                                            Image(systemName: "cpu.fill")
                                                                .font(.system(size: 8))
                                                            Text("Local")
                                                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                                        }
                                                        .foregroundColor(Color(hex: "00f2fe"))
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 2)
                                                        .background(Color(hex: "00f2fe").opacity(0.18))
                                                        .clipShape(Capsule())
                                                    } else if chat.backend == "hermes" {
                                                        Text("Hermes")
                                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                                            .foregroundColor(Color(hex: "b892ff"))
                                                            .padding(.horizontal, 5)
                                                            .padding(.vertical, 2)
                                                            .background(Color(hex: "7c5cff").opacity(0.18))
                                                            .clipShape(Capsule())
                                                    } else {
                                                        Text("262k")
                                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                            .foregroundColor(.white.opacity(0.5))
                                                            .padding(.horizontal, 5)
                                                            .padding(.vertical, 2)
                                                            .background(Color.white.opacity(0.06))
                                                            .clipShape(Capsule())
                                                    }
                                                }
                                                
                                                if let prev = chat.preview, !prev.isEmpty {
                                                    Text(prev)
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.white.opacity(0.45))
                                                        .lineLimit(1)
                                                }
                                            }
                                            .padding(.vertical, 4)
                                        }
                                        .listRowBackground(chat.id == chatVM.currentChatId ? Color.white.opacity(0.08) : Color.clear)
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                chatVM.deleteChat(id: chat.id)
                                            } label: {
                                                Label("Delete Chat", systemImage: "trash")
                                            }
                                            
                                            Button {
                                                renameChatId = chat.id
                                                renameText = chat.title
                                                showRenameAlert = true
                                            } label: {
                                                Label("Rename", systemImage: "pencil")
                                            }
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                chatVM.deleteChat(id: chat.id)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                            
                                            Button {
                                                renameChatId = chat.id
                                                renameText = chat.title
                                                showRenameAlert = true
                                            } label: {
                                                Label("Rename", systemImage: "pencil")
                                            }
                                            .tint(Color(hex: "7c5cff"))
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        
                        // Bottom Footer Toolbar
                        Divider()
                            .background(Color.white.opacity(0.1))
                            .padding(.horizontal, 16)
                        
                        HStack {
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    chatVM.showDrawer = false
                                    chatVM.drawerDragOffset = 0
                                    chatVM.isDraggingDrawer = false
                                }
                                chatVM.showSettings = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.85))
                                    Text("Settings")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 28)
                    }
                    .frame(width: drawerWidth)
                    .background(Color(hex: "12121d"))
                    .ignoresSafeArea(edges: .vertical)
                    .offset(x: clampedOffset)
                    .shadow(color: Color.black.opacity(progress > 0.05 ? 0.45 : 0.0), radius: 16, x: 4, y: 0)
                    .animation(chatVM.isDraggingDrawer ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: clampedOffset)
                    .gesture(
                        DragGesture(minimumDistance: 15)
                            .onChanged { value in
                                guard chatVM.showDrawer else { return }
                                let horizontal = value.translation.width
                                let vertical = abs(value.translation.height)
                                if horizontal < -8 && abs(horizontal) > vertical * 1.2 {
                                    chatVM.isDraggingDrawer = true
                                    chatVM.drawerDragOffset = min(0, horizontal)
                                }
                            }
                            .onEnded { value in
                                guard chatVM.isDraggingDrawer else { return }
                                let velocity = value.predictedEndTranslation.width - value.translation.width
                                if abs(chatVM.drawerDragOffset) > 80 || velocity < -250 {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                        chatVM.showDrawer = false
                                        chatVM.drawerDragOffset = 0
                                        chatVM.isDraggingDrawer = false
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                        chatVM.showDrawer = true
                                        chatVM.drawerDragOffset = 0
                                        chatVM.isDraggingDrawer = false
                                    }
                                }
                            }
                    )
                    .onAppear {
                        syncSelectedTab()
                        Task { await chatVM.loadChats() }
                    }
                    .onChange(of: chatVM.showDrawer) { isShown in
                        if isShown {
                            syncSelectedTab()
                            Task { await chatVM.loadChats() }
                        }
                    }
            }
        }
        .alert("Rename Chat", isPresented: $showRenameAlert) {
            TextField("Chat Title", text: $renameText)
            Button("Save") {
                if let id = renameChatId {
                    chatVM.renameChat(id: id, newTitle: renameText)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
