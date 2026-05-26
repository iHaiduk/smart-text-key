import Foundation
import Security

public final class KeychainHelper: Sendable {
    public static let shared = KeychainHelper()

    private let service = "com.smarttextkey.apikey"
    private let legacyStorageURL: URL
    private let lock = NSLock()

    private init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not access application support directory")
        }
        let directory = appSupport.appendingPathComponent("SmartTextKey")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.legacyStorageURL = directory.appendingPathComponent(".secure_keys.json")
    }

    @discardableResult
    public func save(key: String, value: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let saved: Bool
        if value.isEmpty {
            saved = deleteKeychainValue(for: key)
        } else {
            saved = saveKeychainValue(value, for: key)
        }

        if saved {
            removeLegacyValue(for: key)
        }

        return saved
    }

    public func read(key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }

        if let value = readKeychainValue(for: key) {
            return value
        }

        guard let legacyValue = readLegacyStorage()[key], !legacyValue.isEmpty else {
            return nil
        }

        guard saveKeychainValue(legacyValue, for: key) else {
            return legacyValue
        }

        removeLegacyValue(for: key)
        return legacyValue
    }

    @discardableResult
    public func delete(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let deleted = deleteKeychainValue(for: key)
        if deleted {
            removeLegacyValue(for: key)
        }
        return deleted
    }

    private func keychainQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private func saveKeychainValue(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            return false
        }

        let query = keychainQuery(for: key)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus != errSecItemNotFound {
            print("Smart Text Key [Keychain]: Failed to update key '\(key)': \(message(for: updateStatus))")
            return false
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        }

        print("Smart Text Key [Keychain]: Failed to save key '\(key)': \(message(for: addStatus))")
        return false
    }

    private func readKeychainValue(for key: String) -> String? {
        var query = keychainQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            print("Smart Text Key [Keychain]: Failed to read key '\(key)': \(message(for: status))")
            return nil
        }

        guard let data = item as? Data else {
            print("Smart Text Key [Keychain]: Invalid data for key '\(key)'.")
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychainValue(for key: String) -> Bool {
        let status = SecItemDelete(keychainQuery(for: key) as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        }

        print("Smart Text Key [Keychain]: Failed to delete key '\(key)': \(message(for: status))")
        return false
    }

    private func message(for status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
    }

    private func readLegacyStorage() -> [String: String] {
        guard let data = try? Data(contentsOf: legacyStorageURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private func writeLegacyStorage(_ dict: [String: String]) -> Bool {
        if dict.isEmpty {
            do {
                try FileManager.default.removeItem(at: legacyStorageURL)
                return true
            } catch CocoaError.fileNoSuchFile {
                return true
            } catch {
                print("Smart Text Key [Keychain]: Failed to remove legacy key storage: \(error)")
                return false
            }
        }

        guard let data = try? JSONEncoder().encode(dict) else { return false }

        do {
            try data.write(to: legacyStorageURL, options: .atomic)

            // Enforce strict POSIX permissions 0600 (read & write for owner only)
            let path = legacyStorageURL.path
            var attributes = [FileAttributeKey: Any]()
            attributes[.posixPermissions] = 0o600
            try FileManager.default.setAttributes(attributes, ofItemAtPath: path)
            return true
        } catch {
            print("Smart Text Key [Keychain]: Failed to update legacy key storage: \(error)")
            return false
        }
    }

    private func removeLegacyValue(for key: String) {
        var dict = readLegacyStorage()
        guard dict.removeValue(forKey: key) != nil else { return }
        _ = writeLegacyStorage(dict)
    }
}
