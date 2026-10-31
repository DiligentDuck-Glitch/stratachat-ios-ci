import Foundation
import AVFoundation
import Speech
import Combine
import UIKit

public enum VoiceState: String, Equatable {
    case idle
    case listening
    case thinking
    case speaking
}

@MainActor
public class VoiceEngine: NSObject, ObservableObject {
    public static let shared = VoiceEngine()
    
    // Published UI state
    @Published public var state: VoiceState = .idle
    @Published public var liveTranscript: String = ""
    @Published public var assistantSpokenText: String = ""
    @Published public var audioLevel: Float = 0.0
    @Published public var assistantAudioLevel: Float = 0.0
    @Published public var isMuted: Bool = false
    @Published public var selectedVoice: String = UserDefaults.standard.string(forKey: "strata_voice_id") ?? "af_heart" {
        didSet {
            UserDefaults.standard.set(selectedVoice, forKey: "strata_voice_id")
        }
    }
    @Published public var silenceThreshold: TimeInterval = {
        let saved = UserDefaults.standard.double(forKey: "strata_silence_threshold")
        return saved > 0.1 ? saved : 0.50
    }() {
        didSet {
            UserDefaults.standard.set(silenceThreshold, forKey: "strata_silence_threshold")
        }
    }
    @Published public var availableVoices: [VoiceOption] = []
    @Published public var isReady: Bool = false
    @Published public var errorMessage: String? = nil
    
    // Callbacks
    public var onUserFinishedSpeaking: ((String) -> Void)?
    public var onBargeIn: (() -> Void)?
    
    // Persistent Audio Engine & Recognition
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Audio Playback
    private var audioPlayer: AVAudioPlayer?
    private var audioQueue: [Data] = []
    private var playbackMeteringTimer: Timer?
    private var isAssistantStreamComplete: Bool = false
    private let offlineSynthesizer = AVSpeechSynthesizer()
    
    // Turn taking & silence detection
    private var silenceTimer: Timer?
    
    override private init() {
        super.init()
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        self.offlineSynthesizer.delegate = self
    }
    
    // MARK: - Permissions
    public func requestPermissions() async -> Bool {
        let micAllowed: Bool = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micAllowed else {
            self.errorMessage = "Microphone access is required for Voice Mode."
            return false
        }
        
        let speechAllowed: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAllowed else {
            self.errorMessage = "Speech Recognition permission is required for Voice Mode."
            return false
        }
        
        return true
    }
    
    // MARK: - Start Voice Session
    public func startSession() async {
        guard await requestPermissions() else { return }
        
        stopSession()
        
        // Fetch voices from backend
        Task {
            do {
                let voices = try await APIClient.shared.getVoices()
                if !voices.isEmpty {
                    self.availableVoices = voices
                }
            } catch {
                print("Voice list fetch error: \(error)")
            }
        }
        
        self.isReady = true
        self.state = .listening
        self.liveTranscript = ""
        self.assistantSpokenText = ""
        self.errorMessage = nil
        
        startListening()
    }
    
    // MARK: - Stop Session
    public func stopSession() {
        stopListening()
        stopPlayback()
        
        audioEngine = nil
        self.state = .idle
        self.liveTranscript = ""
        self.assistantSpokenText = ""
        self.audioLevel = 0.0
        self.assistantAudioLevel = 0.0
        self.isReady = false
        
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    // MARK: - Dedicated Listening Turn (Turns 1, 2, 3...)
    private func startListening() {
        // 1. Cleanly cancel and teardown any previous listening instance
        stopListening()
        
        // 2. Configure audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session configuration error: \(error)")
        }
        
        // 3. Create fresh SFSpeechAudioBufferRecognitionRequest
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request
        
        // 4. Initialize engine and attach fresh tap
        if audioEngine == nil {
            audioEngine = AVAudioEngine()
        }
        guard let engine = audioEngine else { return }
        
        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0) // Always remove tap before installing a new one
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            if self.state == .listening && !self.isMuted {
                self.recognitionRequest?.append(buffer)
                
                // Audio RMS metering
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameLength = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frameLength {
                    let sample = channelData[i]
                    sum += sample * sample
                }
                let rms = sqrt(sum / max(1.0, Float(frameLength)))
                let db = 20 * log10(max(rms, 0.0001))
                let normalized = max(0.0, min(1.0, (db + 50) / 50))
                
                Task { @MainActor in
                    self.audioLevel = self.audioLevel * 0.35 + normalized * 0.65
                }
            } else {
                Task { @MainActor in
                    if self.state != .speaking {
                        self.audioLevel = 0.0
                    }
                }
            }
        }
        
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
            self.errorMessage = "Audio engine failed to start: \(error.localizedDescription)"
            return
        }
        
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer()
        }
        
        self.state = .listening
        self.recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                guard self.state == .listening else { return }
                
                if let result = result {
                    let transcribed = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !transcribed.isEmpty else { return }
                    
                    self.liveTranscript = transcribed
                    
                    // Reset silence timer on every new speech fragment
                    self.silenceTimer?.invalidate()
                    self.silenceTimer = Timer.scheduledTimer(withTimeInterval: self.silenceThreshold, repeats: false) { [weak self] _ in
                        guard let self = self else { return }
                        Task { @MainActor in
                            self.commitUserTurn()
                        }
                    }
                }
                
                if let err = error {
                    print("Speech recognition notice: \(err.localizedDescription)")
                }
            }
        }
    }
    
    private func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning {
                engine.stop()
            }
        }
        audioLevel = 0.0
    }
    
    // MARK: - Turn Taking Commit
    private func commitUserTurn() {
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, state == .listening else { return }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        // Stop listening completely for this turn
        stopListening()
        
        self.state = .thinking
        self.audioLevel = 0.0
        self.audioQueue.removeAll()
        self.isAssistantStreamComplete = false
        self.assistantSpokenText = ""
        
        // Notify ChatViewModel to send prompt to Strata Swift
        self.onUserFinishedSpeaking?(text)
    }
    
    // MARK: - Assistant Audio Playback & Streaming
    public func prepareAssistantResponse() {
        self.state = .thinking
        self.audioQueue.removeAll()
        self.isAssistantStreamComplete = false
        self.assistantSpokenText = ""
    }
    
    public func appendAssistantText(_ text: String) {
        self.assistantSpokenText += text
    }
    
    public func enqueueAudioChunk(_ wavData: Data) {
        guard !wavData.isEmpty else { return }
        self.audioQueue.append(wavData)
        
        if audioPlayer == nil || !audioPlayer!.isPlaying {
            playNextChunk()
        }
    }
    
    public func finishAssistantStream() {
        self.isAssistantStreamComplete = true
        if !offlineSynthesizer.isSpeaking && (audioPlayer == nil || !audioPlayer!.isPlaying) && audioQueue.isEmpty {
            onAssistantFinishedSpeaking()
        }
    }
    
    // MARK: - On-Device Offline TTS (Airplane Mode)
    public func speakOfflineSentence(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        
        self.state = .speaking
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.pitchMultiplier = 1.0
        
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        
        offlineSynthesizer.speak(utterance)
        startOfflinePlaybackMetering()
    }
    
    private func startOfflinePlaybackMetering() {
        playbackMeteringTimer?.invalidate()
        playbackMeteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if self.offlineSynthesizer.isSpeaking {
                    let level = Float.random(in: 0.35...0.85)
                    self.assistantAudioLevel = self.assistantAudioLevel * 0.4 + level * 0.6
                } else {
                    self.assistantAudioLevel = 0.0
                }
            }
        }
    }
    
    private func playNextChunk() {
        guard !audioQueue.isEmpty else {
            if isAssistantStreamComplete {
                onAssistantFinishedSpeaking()
            }
            return
        }
        
        let chunk = audioQueue.removeFirst()
        
        do {
            let player = try AVAudioPlayer(data: chunk)
            player.delegate = self
            player.isMeteringEnabled = true
            player.prepareToPlay()
            self.audioPlayer = player
            
            self.state = .speaking
            player.play()
            
            startPlaybackMetering()
        } catch {
            print("AVAudioPlayer error: \(error)")
            playNextChunk()
        }
    }
    
    private func startPlaybackMetering() {
        playbackMeteringTimer?.invalidate()
        playbackMeteringTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer, player.isPlaying else { return }
            player.updateMeters()
            let power = player.averagePower(forChannel: 0)
            let normalized = max(0.0, min(1.0, (power + 45) / 45))
            Task { @MainActor in
                self.assistantAudioLevel = self.assistantAudioLevel * 0.3 + normalized * 0.7
            }
        }
    }
    
    private func stopPlayback() {
        playbackMeteringTimer?.invalidate()
        playbackMeteringTimer = nil
        
        offlineSynthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        audioQueue.removeAll()
        assistantAudioLevel = 0.0
    }
    
    private func onAssistantFinishedSpeaking() {
        stopPlayback()
        
        // Assistant finished speaking: pause briefly for audio daemon teardown, then begin Turn N
        self.liveTranscript = ""
        self.assistantSpokenText = ""
        self.state = .thinking
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms clean settle
            guard self.state != .idle else { return }
            self.startListening()
        }
    }
    
    // MARK: - Instant Barge-In (<20ms)
    public func handleBargeIn() {
        guard state == .speaking || state == .thinking else { return }
        
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        
        // Instantly cut audio and stop listening
        stopPlayback()
        stopListening()
        
        // Notify to cancel backend generation
        onBargeIn?()
        
        self.liveTranscript = ""
        self.assistantSpokenText = ""
        self.state = .thinking
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard self.state != .idle else { return }
            self.startListening()
        }
    }
    
    // MARK: - Controls
    public func toggleMute() {
        isMuted.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if isMuted {
            audioLevel = 0.0
        }
    }
}

// MARK: - AVAudioPlayerDelegate & AVSpeechSynthesizerDelegate
extension VoiceEngine: AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playNextChunk()
        }
    }
    
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.isAssistantStreamComplete && !synthesizer.isSpeaking {
                self.onAssistantFinishedSpeaking()
            }
        }
    }
}
