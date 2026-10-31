import SwiftUI

public struct VoiceModeView: View {
    @ObservedObject var chatVM: ChatViewModel
    @ObservedObject var voiceEngine = VoiceEngine.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var isBreathing: Bool = false
    @State private var showVoicePicker: Bool = false
    
    public init(chatVM: ChatViewModel) {
        self.chatVM = chatVM
    }
    
    private var stateTitle: String {
        switch voiceEngine.state {
        case .listening:
            return voiceEngine.isMuted ? "Microphone Muted" : "Listening…"
        case .thinking:
            return "Thinking (Strata Swift)…"
        case .speaking:
            return "Speaking…"
        case .idle:
            return "Connecting…"
        }
    }
    
    private var primaryColors: [Color] {
        switch voiceEngine.state {
        case .listening:
            return [Color(hex: "7c5cff"), Color(hex: "a855f7"), Color(hex: "4f46e5")]
        case .thinking:
            return [Color(hex: "f59e0b"), Color(hex: "ffd60a"), Color(hex: "d97706")]
        case .speaking:
            return [Color(hex: "10b981"), Color(hex: "06b6d4"), Color(hex: "3b82f6")]
        case .idle:
            return [Color(hex: "64748b"), Color(hex: "475569"), Color(hex: "334155")]
        }
    }
    
    private var activeAmplitude: CGFloat {
        if voiceEngine.state == .speaking {
            return CGFloat(voiceEngine.assistantAudioLevel)
        } else if voiceEngine.state == .listening {
            return CGFloat(voiceEngine.audioLevel)
        } else {
            return 0.15
        }
    }
    
    private var selectedVoiceName: String {
        if let v = voiceEngine.availableVoices.first(where: { $0.id == voiceEngine.selectedVoice }) {
            return v.name
        }
        if voiceEngine.selectedVoice == "bm_fable" {
            return "Fable (JARVIS)"
        }
        return "Heart"
    }
    
    public var body: some View {
        ZStack {
            // OLED Dark Space Background
            Color(hex: "07070b")
                .ignoresSafeArea()
            
            // Atmospheric Radial Glow
            RadialGradient(
                gradient: Gradient(colors: [
                    primaryColors[0].opacity(0.18 + Double(activeAmplitude) * 0.22),
                    primaryColors[1].opacity(0.06),
                    Color.clear
                ]),
                center: .center,
                startRadius: 40,
                endRadius: 280
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Header: Minimize button, Voice capsule & End button
                HStack {
                    // Minimize button (keeps voice session running in background)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        chatVM.showVoiceMode = false
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    
                    Spacer()
                    
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showVoicePicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.badge.magnifyingglass")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(primaryColors[0])
                            
                            Text(selectedVoiceName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    
                    Spacer()
                    
                    // End Voice Session Button
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        voiceEngine.stopSession()
                        chatVM.showVoiceMode = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                
                Spacer()
                
                // Central Fluid Voice Orb (Organic breathing orb)
                ZStack {
                    // Soft ambient backlight glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [primaryColors[0].opacity(0.32 + Double(activeAmplitude) * 0.28), Color.clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 130 + activeAmplitude * 40
                            )
                        )
                        .frame(width: 250 + activeAmplitude * 60, height: 250 + activeAmplitude * 60)
                        .blur(radius: 20)
                    
                    // Core Luminous Orb
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [primaryColors[0], primaryColors[1]],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140 + activeAmplitude * 40, height: 140 + activeAmplitude * 40)
                        .shadow(color: primaryColors[0].opacity(0.6), radius: 26 + activeAmplitude * 20)
                        .scaleEffect(isBreathing ? 1.03 : 0.97)
                        .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: isBreathing)
                        .animation(.spring(response: 0.22, dampingFraction: 0.68), value: activeAmplitude)
                }
                .contentShape(Circle())
                .onTapGesture {
                    if voiceEngine.state == .speaking || voiceEngine.state == .thinking {
                        voiceEngine.handleBargeIn()
                    }
                }
                .onAppear {
                    isBreathing = true
                }
                
                // Status title & subtitle
                VStack(spacing: 6) {
                    Text(stateTitle)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .animation(.easeInOut(duration: 0.2), value: voiceEngine.state)
                    
                    if voiceEngine.state == .speaking {
                        Text("Tap orb or speak to interrupt")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.white.opacity(0.45))
                    } else if voiceEngine.state == .listening {
                        Text("Listening naturally…")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
                .padding(.top, 36)
                
                Spacer()
                
                // Live Spoken Transcript display
                VStack(spacing: 8) {
                    if !voiceEngine.liveTranscript.isEmpty {
                        Text(voiceEngine.liveTranscript)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.95))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else if !voiceEngine.assistantSpokenText.isEmpty && voiceEngine.state == .speaking {
                        Text(voiceEngine.assistantSpokenText)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .frame(height: 70)
                .padding(.bottom, 20)
                
                // Bottom Control Bar
                HStack(spacing: 36) {
                    // Mute / Unmute
                    Button {
                        voiceEngine.toggleMute()
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: voiceEngine.isMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 20))
                                .foregroundColor(voiceEngine.isMuted ? Color(hex: "ff453a") : .white)
                                .frame(width: 58, height: 58)
                                .background(voiceEngine.isMuted ? Color(hex: "ff453a").opacity(0.2) : Color.white.opacity(0.1))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                            
                            Text(voiceEngine.isMuted ? "Unmute" : "Mute")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    
                    // Interrupt / Instant Barge-in Button (Active when assistant speaking)
                    if voiceEngine.state == .speaking || voiceEngine.state == .thinking {
                        Button {
                            voiceEngine.handleBargeIn()
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 26))
                                    .foregroundColor(Color(hex: "ff453a"))
                                    .frame(width: 58, height: 58)
                                    .background(Color(hex: "ff453a").opacity(0.18))
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color(hex: "ff453a").opacity(0.3), lineWidth: 1))
                                
                                Text("Interrupt")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // End Voice Session
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        voiceEngine.stopSession()
                        dismiss()
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 58, height: 58)
                                .background(Color(hex: "ff453a"))
                                .clipShape(Circle())
                                .shadow(color: Color(hex: "ff453a").opacity(0.4), radius: 8, y: 3)
                            
                            Text("End")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                .padding(.bottom, 36)
            }
        }
        .sheet(isPresented: $showVoicePicker) {
            VoicePickerSheet(voiceEngine: voiceEngine)
        }
        .onAppear {
            setupEngineCallbacks()
            if voiceEngine.state == .idle {
                Task {
                    await voiceEngine.startSession()
                }
            }
        }
    }
    
    private func setupEngineCallbacks() {
        voiceEngine.onUserFinishedSpeaking = { [weak chatVM] transcript in
            chatVM?.sendVoiceTurn(text: transcript)
        }
        voiceEngine.onBargeIn = { [weak chatVM] in
            chatVM?.stop()
        }
    }
}

// MARK: - Voice Picker Sheet
struct VoicePickerSheet: View {
    @ObservedObject var voiceEngine: VoiceEngine
    @Environment(\.dismiss) private var dismiss
    
    private var voicesToDisplay: [VoiceOption] {
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
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "09090f").ignoresSafeArea()
                
                List {
                    // Turn Timing Controls
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Silence Pause Detection")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(String(format: "%.2fs", voiceEngine.silenceThreshold))
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: "7c5cff"))
                            }
                            
                            Picker("Response Speed", selection: $voiceEngine.silenceThreshold) {
                                Text("Fast (0.4s)").tag(0.40)
                                Text("Balanced (0.5s)").tag(0.50)
                                Text("Relaxed (0.75s)").tag(0.75)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Conversation Timing")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    } footer: {
                        Text("How long Strata waits in silence before deciding you finished speaking.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .listRowBackground(Color(hex: "13131c"))
                    
                    Section {
                        ForEach(voicesToDisplay) { voice in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                voiceEngine.selectedVoice = voice.id
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(voice.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.white)
                                            
                                            if voice.flagship == true {
                                                Text("DEFAULT")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(Color(hex: "7c5cff"))
                                                    .foregroundColor(.white)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        
                                        HStack(spacing: 8) {
                                            if let accent = voice.accent {
                                                Text(accent)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.white.opacity(0.5))
                                            }
                                            if let tag = voice.tag {
                                                Text("·  \(tag)")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.white.opacity(0.5))
                                            }
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if voiceEngine.selectedVoice == voice.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(Color(hex: "7c5cff"))
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color(hex: "13131c"))
                        }
                    } header: {
                        Text("Kokoro Studio 24kHz Voices")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    } footer: {
                        Text("Synthesized on-device via host CPU ONNX. Zero network cloud fee.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Voice & Timing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Color(hex: "7c5cff"))
                }
            }
        }
    }
}
