import Foundation
import Security
import Combine

/// Riot and Gemini keys in the Keychain, pasted in because a personal Riot key expires daily.
nonisolated enum APIKeys {
    static var riot: String {
        get { read("riotAPIKey") }
        set { write(newValue, account: "riotAPIKey") }
    }

    static var gemini: String {
        get { read("geminiAPIKey") }
        set { write(newValue, account: "geminiAPIKey") }
    }

    /// Seeds keys from Secrets.swift once, so a key the user deliberately cleared stays cleared.
    @MainActor
    static func seedFromSecretsIfNeeded() {
        let seededKey = "apiKeysSeededFromSecrets"
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        if riot.isEmpty { riot = Secrets.riotAPIKey }
        if gemini.isEmpty { gemini = Secrets.geminiAPIKey }
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    private static let service = "Climb"

    private static func read(_ account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Update in place, add only when absent: delete-then-add loses the old key if the add fails.
    private static func write(_ value: String, account: String) {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        guard !value.isEmpty else {
            SecItemDelete(identity as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(identity as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

/// Set when Riot rejects the key, so the app can ask for today's instead of failing silently.
final class APIKeyPrompt: ObservableObject {
    static let shared = APIKeyPrompt()
    /// Stays true until a sync or a saved key clears it, so the Matches banner keeps showing.
    @Published var riotKeyRejected = false {
        didSet { if riotKeyRejected && !oldValue { isPresented = true } }
    }
    /// Opens once per rejection: every later request also 401s, and reopening on each buried the
    /// cached games. After Cancel the banner reopens it.
    @Published var isPresented = false
}
