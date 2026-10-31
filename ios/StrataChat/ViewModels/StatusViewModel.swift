import Foundation
import Combine

@MainActor
public class StatusViewModel: ObservableObject {
    @Published public var status: ServerStatus?
    @Published public var isOnline: Bool = false
    @Published public var elapsedSeconds: Int = 0
    @Published public var errorMessage: String?
    @Published public var isPowerActionInProgress: Bool = false
    @Published public var powerFeedback: String? = nil
    @Published public var switchingToVariant: String? = nil
    
    private var timer: Timer?
    private var elapsedTimer: Timer?
    private let client = APIClient.shared
    
    public init() {
        startPolling()
    }
    
    deinit {
        timer?.invalidate()
        elapsedTimer?.invalidate()
    }
    
    public func startPolling() {
        timer?.invalidate()
        elapsedTimer?.invalidate()
        
        Task { await refresh() }
        
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
        
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let st = self.status,
                      (st.state == "loading" || st.state == "switching"),
                      let since = st.loadingSince else {
                    self?.elapsedSeconds = 0
                    return
                }
                self.elapsedSeconds = max(0, Int(Date().timeIntervalSince1970 - since))
            }
        }
    }
    
    private var consecutiveFailures: Int = 0
    
    public func refresh() async {
        await client.ensureAuthenticated()
        do {
            let st = try await client.getStatus()
            self.status = st
            self.isOnline = true
            self.consecutiveFailures = 0
            self.errorMessage = nil
        } catch {
            self.consecutiveFailures += 1
            if self.consecutiveFailures >= 4 {
                self.isOnline = false
            }
        }
    }
    
    public func wake() async {
        await client.ensureAuthenticated()
        do {
            try await client.warmup()
            await refresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    public func unload() async {
        await client.ensureAuthenticated()
        do {
            try await client.unload()
            await refresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    public func switchVariant(_ variant: String) async {
        self.switchingToVariant = variant
        await client.ensureAuthenticated()
        do {
            try await client.switchVariant(variant: variant)
            await refresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
        self.switchingToVariant = nil
    }
    
    // MARK: - PC Power Controls (E2EE Protected)
    public func wakePC() {
        WakeOnLAN.sendMagicPacket()
        self.powerFeedback = "⚡ Magic packet broadcast sent! Waking PC..."
        Task {
            for _ in 1...12 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await refresh()
                if self.isOnline {
                    self.powerFeedback = "⚡ PC is online and ready!"
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    self.powerFeedback = nil
                    return
                }
            }
            if !self.isOnline {
                self.powerFeedback = "⚡ Packet sent. If asleep, ensure phone is on home Wi-Fi."
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                self.powerFeedback = nil
            }
        }
    }
    
    public func sleepPC() async {
        isPowerActionInProgress = true
        defer { isPowerActionInProgress = false }
        do {
            let msg = try await client.triggerPowerAction("suspend", confirm: true)
            self.powerFeedback = "🌙 \(msg)"
            self.isOnline = false
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self.powerFeedback = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    public func shutdownPC() async {
        isPowerActionInProgress = true
        defer { isPowerActionInProgress = false }
        do {
            let msg = try await client.triggerPowerAction("poweroff", confirm: true)
            self.powerFeedback = "⏻ \(msg)"
            self.isOnline = false
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self.powerFeedback = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    public func setStealthMode(enabled: Bool) async {
        isPowerActionInProgress = true
        defer { isPowerActionInProgress = false }
        do {
            let action = enabled ? "stealth" : "normal"
            let msg = try await client.triggerPowerAction(action)
            self.powerFeedback = enabled ? "🌙 \(msg)" : "☀️ \(msg)"
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self.powerFeedback = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}
