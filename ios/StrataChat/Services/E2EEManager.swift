import Foundation
import CryptoKit
import Security
import Combine

public class E2EEManager: ObservableObject {
    public static let shared = E2EEManager()
    
    private let kKeychainService = "com.noir.stratachat"
    private let kKeychainAccount = "e2ee_passphrase"
    
    @Published public var passphrase: String = "" {
        didSet {
            savePassphrase(passphrase)
            updateKey()
        }
    }
    
    @Published public var isEnabled: Bool = false
    @Published public var serverHasKey: Bool = false
    
    private var symmetricKey: SymmetricKey?
    
    private init() {
        let loaded = loadPassphrase() ?? ""
        self.passphrase = loaded
        updateKey()
    }
    
    private func updateKey() {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            symmetricKey = nil
            isEnabled = false
        } else {
            let saltPrefix = "strata-chat-e2ee-v1:\(trimmed)"
            let hash = SHA256.hash(data: Data(saltPrefix.utf8))
            symmetricKey = SymmetricKey(data: hash)
            isEnabled = true
        }
    }
    
    public func checkServerStatus() async {
        let active = await APIClient.shared.getE2EEStatus()
        await MainActor.run {
            self.serverHasKey = active
        }
    }
    
    // Encrypt Data -> ["e2ee": true, "iv": base64, "data": base64]
    public func encrypt(data: Data) -> [String: Any]? {
        guard let key = symmetricKey else { return nil }
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            let ivData = Data(sealed.nonce)
            let cipherAndTag = sealed.ciphertext + sealed.tag
            return [
                "e2ee": true,
                "iv": ivData.base64EncodedString(),
                "data": cipherAndTag.base64EncodedString()
            ]
        } catch {
            print("E2EE encryption error: \(error)")
            return nil
        }
    }
    
    public func encrypt(dict: [String: Any]) -> [String: Any]? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return encrypt(data: data)
    }
    
    // Decrypt (iv: base64, data: base64) -> Data
    public func decrypt(iv: String, data: String) -> Data? {
        guard let key = symmetricKey else { return nil }
        guard let ivData = Data(base64Encoded: iv),
              let cipherAndTag = Data(base64Encoded: data) else {
            return nil
        }
        do {
            let combined = ivData + cipherAndTag
            let sealed = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(sealed, using: key)
        } catch {
            print("E2EE decryption error: \(error)")
            return nil
        }
    }
    
    // Keychain helpers
    private func savePassphrase(_ pass: String) {
        let trimmed = pass.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: kKeychainService,
                kSecAttrAccount as String: kKeychainAccount
            ]
            SecItemDelete(query as CFDictionary)
            return
        }
        
        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kKeychainService,
            kSecAttrAccount as String: kKeychainAccount
        ]
        
        SecItemDelete(query as CFDictionary)
        
        var newAttributes = query
        newAttributes[kSecValueData as String] = data
        newAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        
        SecItemAdd(newAttributes as CFDictionary, nil)
    }
    
    private func loadPassphrase() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: kKeychainService,
            kSecAttrAccount as String: kKeychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
