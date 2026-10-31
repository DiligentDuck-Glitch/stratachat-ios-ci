import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable {
    case connection = "Connection"
    case security = "Security"
    case voice = "Voice"
    
    public var id: String { rawValue }
}

public struct SettingsView: View {
    @ObservedObject var config = ServerConfig.shared
    @ObservedObject var e2ee = E2EEManager.shared
    @ObservedObject var statusVM: StatusViewModel
    @ObservedObject var voiceEngine = VoiceEngine.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab: SettingsTab = .connection
    @State private var serverURL: String = ""
    @State private var passwordInput: String = ""
    @State private var e2eePassphraseInput: String = ""
    @State private var isTesting: Bool = false
    @State private var statusMessage: String? = nil
    @State private var isError: Bool = false
    @State private var e2eeMessage: String? = nil
    
    public init(statusVM: StatusViewModel) {
        self.statusVM = statusVM
    }
    
    private var defaultVoices: [VoiceOption] {
        if !voiceEngine.availableVoices.isEmpty {
            return voiceEngine.availableVoices
        }
        return [
            VoiceOption(id: "af_heart", name: "Heart", gender: "female", accent: "American", tag: "Warm & Natural", flagship: true),
            VoiceOption(id: "bm_fable", name: "Fable (JARVIS)", gender: "male", accent: "British", tag: "Refined & Crisp", flagship: false),
            VoiceOption(id: "af_bella", name: "Bella", gender: "female", accent: "American", tag: "Bright & Expressive", flagship: false),
            VoiceOption(id: "am_adam", name: "Adam", gender: "male", accent: "American", tag: "Deep & Grounded", flagship: false),
            VoiceOption(id: "af_sky", name: "Sky", gender: "female", accent: "American", tag: "Friendly & Clear", flagship: false),
            VoiceOption(id: "am_michael", name: "Michael", gender: "male", accent: "American", tag: "Conversational", flagship: false),
            VoiceOption(id: "bf_emma", name: "Emma", gender: "female", accent: "British", tag: "Polished", flagship: false),
            VoiceOption(id: "bm_george", name: "George", gender: "male", accent: "British", tag: "Classic", flagship: false),
        ]
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "09090f").ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top Segmented Tab Picker
                    Picker("Settings Section", selection: $selectedTab) {
                        ForEach(SettingsTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(hex: "12121d"))
                    
                    Divider().background(Color.white.opacity(0.1))
                    
                    ScrollView {
                        VStack(spacing: 16) {
                            switch selectedTab {
                            case .connection:
                                connectionTab
                            case .security:
                                securityTab
                            case .voice:
                                voiceTab
                            }
                            
                            Spacer(minLength: 24)
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(hex: "7c5cff"))
                }
            }
            .onAppear {
                self.serverURL = config.baseURLString
                self.passwordInput = config.savedPassword
                self.e2eePassphraseInput = e2ee.passphrase
                Task {
                    await e2ee.checkServerStatus()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Connection Tab
    
    @ViewBuilder
    private var connectionTab: some View {
        VStack(spacing: 16) {
            // Rendering preferences
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transposed tables")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Show 3+ column tables as one card per row instead of a wide table you have to pan.")
                            .font(.system(size: 11))
                            .opacity(0.6)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { UserDefaults.standard.object(forKey: "transposed_tables_enabled") as? Bool ?? true },
                        set: { UserDefaults.standard.set($0, forKey: "transposed_tables_enabled") }
                    ))
                    .labelsHidden()
                }
            }

            // Server URL Section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("SERVER CONNECTION")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text(config.isUsingRemote ? "Remote (Cellular)" : "Home Wi-Fi")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(config.isUsingRemote ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                        .foregroundColor(config.isUsingRemote ? .blue : .green)
                        .clipShape(Capsule())
                }
                
                // Preset Switchers
                HStack(spacing: 8) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        config.switchToLocal()
                        serverURL = config.baseURLString
                        testConnection()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wifi")
                            Text("Home Wi-Fi")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(config.isUsingLocal ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(config.isUsingLocal ? Color(hex: "7c5cff") : Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        config.switchToRemote()
                        serverURL = config.baseURLString
                        testConnection()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Remote Tunnel")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(config.isUsingRemote ? .white : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(config.isUsingRemote ? Color(hex: "7c5cff") : Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                
                TextField("http://192.168.1.39:8765", text: $serverURL)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                HStack {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task {
                            isTesting = true
                            statusMessage = "Syncing live tunnel..."
                            let success = await config.syncTunnelFromGist()
                            if success {
                                serverURL = config.baseURLString
                                testConnection()
                            } else {
                                statusMessage = "Sync failed (check master passphrase in Security tab)"
                                isError = true
                                isTesting = false
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sync Live Tunnel")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "7c5cff"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(hex: "7c5cff").opacity(0.12))
                        .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    Text("Device: \(config.deviceId.prefix(8))...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                
                Text("Tap 'Home Wi-Fi' when at home on Wi-Fi. Tap 'Remote Tunnel' when on 5G/LTE Cellular or away.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(14)
            .background(Color(hex: "181826"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            // Authentication Section
            VStack(alignment: .leading, spacing: 8) {
                Text("AUTHENTICATION")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                
                SecureField("Server Password", text: $passwordInput)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Button {
                    testConnection()
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "link")
                        }
                        Text("Connect & Save")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(hex: "7c5cff"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isTesting || serverURL.isEmpty)
                
                if let msg = statusMessage {
                    Text(msg)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isError ? .red : .green)
                        .padding(.top, 4)
                }
            }
            .padding(14)
            .background(Color(hex: "181826"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            // Connected Status
            HStack {
                Circle()
                    .fill(statusVM.isOnline ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(statusVM.isOnline ? "Connected to RTX 5070 Ti" : "Offline / Unreachable")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 8)
        }
    }
    
    // MARK: - Security & E2EE Tab
    
    @ViewBuilder
    private var securityTab: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: e2ee.isEnabled ? "lock.shield.fill" : "shield.slash")
                        .foregroundColor(e2ee.isEnabled ? Color.green : Color.white.opacity(0.4))
                    Text("ZERO-KNOWLEDGE E2EE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    if e2ee.isEnabled {
                        Text("AES-256-GCM")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
                
                Text("All messages, prompts, images, tools, and token streams are encrypted directly on your phone and decrypted only inside your PC's GPU memory. Cloudflare, WARP, ISPs, and AI assistants cannot read them.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                
                SecureField("Secret E2EE Passphrase", text: $e2eePassphraseInput)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                HStack(spacing: 10) {
                    Button {
                        saveE2EEPassphrase()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.shield")
                            Text("Save Key")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Color.green.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    if e2ee.isEnabled {
                        Button {
                            clearE2EEPassphrase()
                        } label: {
                            Text("Disable")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.red.opacity(0.8))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(Color.red.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                
                if let em = e2eeMessage {
                    Text(em)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                }
                
                if e2ee.isEnabled {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(e2ee.serverHasKey ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(e2ee.serverHasKey ? "PC host key verified and ready" : "Run ./set-e2ee-key.sh on your PC to enable host-side key")
                            .font(.system(size: 11))
                            .foregroundColor(e2ee.serverHasKey ? .green : .orange)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(14)
            .background(Color(hex: "181826"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // MARK: - Voice & Audio Tab
    
    @ViewBuilder
    private var voiceTab: some View {
        VStack(spacing: 16) {
            // Silence & Timing Control
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("CONVERSATION RESPONSIVENESS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text(String(format: "%.2fs pause", voiceEngine.silenceThreshold))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "7c5cff"))
                }
                
                Picker("Response Speed", selection: $voiceEngine.silenceThreshold) {
                    Text("Fast (0.4s)").tag(0.40)
                    Text("Balanced (0.5s)").tag(0.50)
                    Text("Relaxed (0.75s)").tag(0.75)
                }
                .pickerStyle(.segmented)
                
                Text("How long Strata waits in silence before deciding you finished speaking.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(14)
            .background(Color(hex: "181826"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            // Kokoro Voice Persona Selection
            VStack(alignment: .leading, spacing: 10) {
                Text("VOICE PERSONA (KOKORO-82M)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                
                VStack(spacing: 2) {
                    ForEach(defaultVoices) { voice in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            voiceEngine.selectedVoice = voice.id
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(voice.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white)
                                        
                                        if voice.flagship == true {
                                            Text("DEFAULT")
                                                .font(.system(size: 8, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color(hex: "7c5cff"))
                                                .foregroundColor(.white)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    
                                    HStack(spacing: 6) {
                                        if let accent = voice.accent {
                                            Text(accent)
                                                .font(.system(size: 11))
                                                .foregroundColor(.white.opacity(0.45))
                                        }
                                        if let tag = voice.tag {
                                            Text("·  \(tag)")
                                                .font(.system(size: 11))
                                                .foregroundColor(.white.opacity(0.45))
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                if voiceEngine.selectedVoice == voice.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(Color(hex: "7c5cff"))
                                } else {
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1.5)
                                        .frame(width: 18, height: 18)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 10)
                            .background(voiceEngine.selectedVoice == voice.id ? Color.white.opacity(0.06) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(hex: "181826"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            // Sentence Streaming Info
            HStack(spacing: 10) {
                Image(systemName: "bolt.horizontal.fill")
                    .foregroundColor(Color(hex: "7c5cff"))
                    .font(.system(size: 14))
                Text("Spoken in natural sentence chunks with sequential reassembly queue for zero skipping or out-of-order speech.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
            }
            .padding(12)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Actions
    
    private func saveE2EEPassphrase() {
        let clean = e2eePassphraseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        e2ee.passphrase = clean
        e2eeMessage = clean.isEmpty ? "E2EE disabled." : "✓ Passphrase saved to Keychain! E2EE active."
        Task {
            await e2ee.checkServerStatus()
        }
    }
    
    private func clearE2EEPassphrase() {
        e2eePassphraseInput = ""
        e2ee.passphrase = ""
        e2eeMessage = "E2EE disabled."
    }
    
    private func testConnection() {
        isTesting = true
        statusMessage = nil
        isError = false
        
        config.baseURLString = serverURL
        
        Task {
            do {
                if !passwordInput.isEmpty {
                    _ = try await APIClient.shared.login(password: passwordInput)
                }
                await statusVM.refresh()
                await e2ee.checkServerStatus()
                if statusVM.isOnline {
                    statusMessage = "Successfully connected!"
                    isError = false
                } else {
                    statusMessage = "Server connected, but could not retrieve status."
                    isError = true
                }
            } catch {
                statusMessage = error.localizedDescription
                isError = true
            }
            isTesting = false
        }
    }
}
