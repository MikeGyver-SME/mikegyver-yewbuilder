import Foundation
import Security

/// FTP password storage, iOS Keychain only.
///
/// The password is never written to UserDefaults, to a file, to the build
/// log, or to the builder server. It lives in the Keychain under the FTP
/// username as the account, so re-entry is optional: Build reads the saved
/// password and only asks when there is none saved.
///
/// The builder server never sees the password at all — it only returns the
/// built files, and this phone uploads them over FTP itself.
enum KeychainService {
    private static let service = "studio.mikegyver.yewbuilder.ftp"

    /// The account the password is stored under (the FTP username).
    static func save(password: String, account: String) -> Bool {
        guard let data = password.data(using: .utf8), !account.isEmpty else { return false }
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(account: String) -> String? {
        guard !account.isEmpty else { return nil }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8),
              !password.isEmpty else { return nil }
        return password
    }

    static func hasPassword(account: String) -> Bool {
        load(account: account) != nil
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        guard !account.isEmpty else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
