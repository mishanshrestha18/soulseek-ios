import Foundation
import Security

/// Soulseek has no password reset — the server rejects an unknown username as
/// a login failure, and there is no recovery flow. Credentials therefore have
/// to survive locally, and the Keychain is the only place they belong.
enum Credentials {
    private static let service = "org.slsknet.soulseek"
    private static let usernameKey = "lastUsername"

    struct Stored: Equatable {
        var username: String
        var password: String
    }

    static func load() -> Stored? {
        guard let username = UserDefaults.standard.string(forKey: usernameKey),
              !username.isEmpty,
              let password = password(for: username) else { return nil }
        return Stored(username: username, password: password)
    }

    static func save(username: String, password: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username
        ]
        // SecItemUpdate cannot create, SecItemAdd cannot replace. Deleting
        // first is the usual way to get upsert semantics out of the two.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(password.utf8)
        // The app only reads this while running and reconnects on launch, so
        // first-unlock is the right tradeoff: available after a reboot once
        // the user has unlocked, never synced to other devices.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { return }
        UserDefaults.standard.set(username, forKey: usernameKey)
    }

    static func clear() {
        guard let username = UserDefaults.standard.string(forKey: usernameKey) else { return }
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username
        ] as CFDictionary)
        UserDefaults.standard.removeObject(forKey: usernameKey)
    }

    private static func password(for username: String) -> String? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: username,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
