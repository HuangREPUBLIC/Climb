import Foundation
import Security
import Combine

/// The Riot and Gemini keys, kept in the Keychain and pasted in from the app.
///
/// A personal Riot key expires every 24 hours; compiled into the build, that
/// meant a rebuild every day just to keep syncing.
nonisolated enum APIKeys {
    static var riot: String {
        get { read("riotAPIKey") }
        set { write(newValue, account: "riotAPIKey") }
    }

    static var gemini: String {
        get { read("geminiAPIKey") }
        set { write(newValue, account: "geminiAPIKey") }
    }

    /// First launch after keys moved here: carry over whatever Secrets.swift
    /// holds, so nobody has to paste keys they already configured.
    /// Once only, so a key the user deliberately cleared stays cleared.
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

    /// Update in place, adding only when absent — delete-then-add would lose
    /// the old key if the add failed.
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

/// Raised when Riot rejects the key, so the app can ask for today's instead
/// of failing every sync silently.
@MainActor
final class APIKeyPrompt: ObservableObject {
    static let shared = APIKeyPrompt()
    @Published var riotKeyRejected = false
}
