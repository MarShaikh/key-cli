import Foundation
import Security

enum KeychainError: Error, CustomStringConvertible {
    case notFound(String)
    case notOwned(String)
    case status(OSStatus)

    var description: String {
        switch self {
        case .notFound(let name):
            return "No key found for service: \(name)"
        case .notOwned(let name):
            return "\(name) was stored by the old shell function; run `key adopt \(name)` first"
        case .status(let status):
            return (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        }
    }
}

/// Generic-password items in the login keychain, scoped to the current user.
///
/// Items are created by this binary, so the keychain ACL trusts only this binary.
/// Anything else, including `security find-generic-password -w`, gets a keychain-password dialog.
struct Keychain {
    /// Stored as kSecAttrDescription ("Kind" in Keychain Access); `list` finds our items by it.
    static let kind = "key-cli secret"

    let account = NSUserName()

    func read(_ name: String) throws -> Data {
        var query = base(name)
        query[kSecReturnData as String] = true
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status != errSecItemNotFound else { throw KeychainError.notFound(name) }
        guard status == errSecSuccess, let data = out as? Data else { throw KeychainError.status(status) }
        return data
    }

    /// Adds the item, or replaces it if this binary already owns it.
    func write(_ name: String, _ secret: Data) throws {
        try delete(name, missingOK: true)
        var item = base(name)
        item[kSecValueData as String] = secret
        item[kSecAttrLabel as String] = name
        item[kSecAttrDescription as String] = Keychain.kind
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func delete(_ name: String, missingOK: Bool = false) throws {
        let status = SecItemDelete(base(name) as CFDictionary)
        switch status {
        case errSecSuccess: return
        case errSecItemNotFound where missingOK: return
        case errSecItemNotFound: throw KeychainError.notFound(name)
        case errSecInvalidOwnerEdit: throw KeychainError.notOwned(name)
        default: throw KeychainError.status(status)
        }
    }

    /// Names of items this tool stored. Reads attributes only, never secrets.
    func names() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrDescription as String: Keychain.kind,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = out as? [[String: Any]] else { throw KeychainError.status(status) }
        return items.compactMap { $0[kSecAttrService as String] as? String }.sorted()
    }

    private func base(_ name: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: name,
            kSecAttrAccount as String: account,
        ]
    }
}
