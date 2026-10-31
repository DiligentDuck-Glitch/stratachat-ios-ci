import Foundation
import Combine

public class ServerConfig: ObservableObject {
    public static let shared = ServerConfig()
    
    public static let defaultLocalURL = "http://192.168.1.39:8765"
    public static let defaultRemoteURL = "https://replace-me.invalid"
    
    private let kBaseURL = "stratachat_base_url"
    private let kLocalURL = "stratachat_local_url"
    private let kRemoteURL = "stratachat_remote_url"
    private let kAuthToken = "stratachat_auth_token"
    private let kSavedPassword = "stratachat_saved_password"
    
    private let kDeviceId = "stratachat_device_id"
    
    public var deviceId: String {
        if let saved = UserDefaults.standard.string(forKey: kDeviceId), !saved.isEmpty {
            return saved
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: kDeviceId)
        return newId
    }
    
    public static let gistSyncURL = "https://api.github.com/gists/393960ed4ae2f1bb67c98978e22846d3"
    
    @Published public var isSyncingTunnel: Bool = false
    @Published public var tunnelSyncError: String? = nil
    
    public func syncTunnelFromGist() async -> Bool {
        guard let url = URL(string: Self.gistSyncURL) else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return false }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let files = json["files"] as? [String: Any],
                  let endpointFile = files["strata-endpoint.json"] as? [String: Any],
                  let content = endpointFile["content"] as? String,
                  let contentData = content.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any],
                  let iv = payload["iv"] as? String,
                  let encData = payload["data"] as? String else {
                return false
            }
            
            // Decrypt with E2EEManager
            guard let decryptedData = E2EEManager.shared.decrypt(iv: iv, data: encData),
                  let dict = try? JSONSerialization.jsonObject(with: decryptedData) as? [String: Any],
                  let newTunnelURL = dict["url"] as? String,
                  !newTunnelURL.isEmpty else {
                return false
            }
            
            await MainActor.run {
                if self.remoteURLString != newTunnelURL {
                    print("[ServerConfig] Auto-synced new tunnel URL: \(newTunnelURL)")
                    self.remoteURLString = newTunnelURL
                    if self.isUsingRemote {
                        self.baseURLString = newTunnelURL
                    }
                }
            }
            return true
        } catch {
            print("[ServerConfig] Gist sync failed: \(error)")
            return false
        }
    }
    
    @Published public var baseURLString: String {
        didSet {
            UserDefaults.standard.set(baseURLString, forKey: kBaseURL)
        }
    }
    
    @Published public var localURLString: String {
        didSet {
            UserDefaults.standard.set(localURLString, forKey: kLocalURL)
        }
    }
    
    @Published public var remoteURLString: String {
        didSet {
            UserDefaults.standard.set(remoteURLString, forKey: kRemoteURL)
        }
    }
    
    @Published public var authToken: String? {
        didSet {
            if let token = authToken {
                KeychainHelper.save(key: kAuthToken, value: token)
            } else {
                KeychainHelper.delete(key: kAuthToken)
            }
        }
    }
    
    @Published public var savedPassword: String {
        didSet {
            KeychainHelper.save(key: kSavedPassword, value: savedPassword)
        }
    }
    
    public var isConfigured: Bool {
        return cleanBaseURL != nil && (!savedPassword.isEmpty || authToken != nil)
    }
    
    public init() {
        let savedLocal = UserDefaults.standard.string(forKey: kLocalURL) ?? Self.defaultLocalURL
        let resolvedLocal = savedLocal.isEmpty ? Self.defaultLocalURL : savedLocal
        self.localURLString = resolvedLocal
        
        let savedRemote = UserDefaults.standard.string(forKey: kRemoteURL) ?? Self.defaultRemoteURL
        let resolvedRemote = (savedRemote.isEmpty || savedRemote.contains("endorsed-amounts-meal-forget") || savedRemote.contains("lovely-mainly-hair-desired")) ? Self.defaultRemoteURL : savedRemote
        self.remoteURLString = resolvedRemote
        
        let saved = UserDefaults.standard.string(forKey: kBaseURL)
        if saved == nil || saved?.isEmpty == true || saved == "http://192.168.1.100:8765" || saved?.contains("endorsed-amounts-meal-forget") == true || saved?.contains("lovely-mainly-hair-desired") == true {
            self.baseURLString = resolvedRemote.isEmpty ? resolvedLocal : resolvedRemote
        } else {
            self.baseURLString = saved!
        }
        
        // Discard legacy burned credentials from UserDefaults
        UserDefaults.standard.removeObject(forKey: kSavedPassword)
        UserDefaults.standard.removeObject(forKey: kAuthToken)
        
        self.authToken = KeychainHelper.load(key: kAuthToken)
        self.savedPassword = KeychainHelper.load(key: kSavedPassword) ?? ""
    }
    
    public var cleanBaseURL: URL? {
        var str = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !str.hasPrefix("http://") && !str.hasPrefix("https://") {
            str = "http://" + str
        }
        if str.hasSuffix("/") {
            str = String(str.dropLast())
        }
        return URL(string: str)
    }
    
    public var isUsingLocal: Bool {
        baseURLString.contains("192.168.") || baseURLString.contains("10.") || baseURLString.contains("127.0.0.1")
    }
    
    public var isUsingRemote: Bool {
        baseURLString.contains("trycloudflare.com") || baseURLString.contains(".cloudflare.")
    }
    
    public func switchToLocal() {
        self.baseURLString = localURLString
    }
    
    public func switchToRemote() {
        self.baseURLString = remoteURLString
    }
    
    public var alternativeURL: String? {
        if isUsingLocal {
            return remoteURLString.isEmpty ? nil : remoteURLString
        } else {
            return localURLString.isEmpty ? nil : localURLString
        }
    }
    
    public var isAuthenticated: Bool {
        return authToken != nil && !(authToken?.isEmpty ?? true)
    }
}
