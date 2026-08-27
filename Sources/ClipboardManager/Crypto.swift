import Foundation
import CryptoKit
import Security

/// Errors raised while loading or creating the app's encryption key.
enum KeychainError: LocalizedError {
    case unexpectedItemFormat
    case status(OSStatus, operation: String)

    var errorDescription: String? {
        switch self {
        case .unexpectedItemFormat:
            return "The encryption key stored in the Keychain is not in the expected format."
        case let .status(status, operation):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain failed to \(operation): \(detail)"
        }
    }
}

/// Loads the AES key backing the app's at-rest encryption.
enum KeychainKeyStore {
    /// Fetches the stored 256-bit key, generating and saving one on first run.
    ///
    /// Only a genuine `errSecItemNotFound` results in a new key. Any other failure - a locked
    /// keychain returning `errSecInteractionNotAllowed`, for instance - is thrown, because
    /// minting a replacement key in that situation would orphan every clip already on disk.
    static func loadOrCreateKey(service: String, account: String) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let keyData = result as? Data else {
                throw KeychainError.unexpectedItemFormat
            }
            return SymmetricKey(data: keyData)

        case errSecItemNotFound:
            let newKey = SymmetricKey(size: .bits256)
            let keyData = newKey.withUnsafeBytes { Data($0) }

            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: keyData,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
            ]

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.status(addStatus, operation: "store a new encryption key")
            }
            return newKey

        default:
            throw KeychainError.status(status, operation: "read the encryption key")
        }
    }
}

/// AES-256-GCM encryption over a single key. Each call generates a fresh random nonce, which
/// travels inside the returned combined blob (nonce + ciphertext + tag) rather than being
/// stored separately.
struct Cipher {
    private let key: SymmetricKey

    init(key: SymmetricKey) {
        self.key = key
    }

    func encrypt(_ data: Data) -> Data? {
        try? AES.GCM.seal(data, using: key).combined
    }

    func decrypt(_ data: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    /// Encrypts UTF-8 text to a base64 blob suitable for a TEXT column.
    func encrypt(_ text: String) -> String? {
        guard let data = text.data(using: .utf8) else { return nil }
        return encrypt(data)?.base64EncodedString()
    }

    /// Reverses `encrypt(_ text:)`. Returns nil for anything that isn't valid ciphertext for
    /// this key, which callers rely on to distinguish encrypted values from legacy plaintext.
    func decrypt(_ base64Text: String) -> String? {
        guard let data = Data(base64Encoded: base64Text),
              let plaintext = decrypt(data) else { return nil }
        return String(data: plaintext, encoding: .utf8)
    }

    /// True when the value is ciphertext this key can open. GCM's authentication tag makes a
    /// false positive on arbitrary plaintext infeasible, so migrations use this to stay idempotent.
    func isEncrypted(_ base64Text: String) -> Bool {
        decrypt(base64Text) != nil
    }

    func isEncrypted(_ data: Data) -> Bool {
        decrypt(data) != nil
    }
}
