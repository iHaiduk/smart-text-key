import Foundation

public final class KeychainHelper: Sendable {
    public static let shared = KeychainHelper()
    
    private let storageURL: URL
    private let lock = NSLock()
    
    private init() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Could not access application support directory")
        }
        let directory = appSupport.appendingPathComponent("SmartTextKey")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.storageURL = directory.appendingPathComponent(".secure_keys.json")
    }
    
    private func readStorage() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        
        guard let data = try? Data(contentsOf: storageURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }
    
    private func writeStorage(_ dict: [String: String]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard let data = try? JSONEncoder().encode(dict) else { return false }
        
        do {
            try data.write(to: storageURL, options: .atomic)
            
            // Enforce strict POSIX permissions 0600 (read & write for owner only)
            let path = storageURL.path
            var attributes = [FileAttributeKey: Any]()
            attributes[.posixPermissions] = 0o600
            try FileManager.default.setAttributes(attributes, ofItemAtPath: path)
            return true
        } catch {
            print("Smart Text Key [SecureStorage]: Failed to save secure keys: \(error)")
            return false
        }
    }
    
    @discardableResult
    public func save(key: String, value: String) -> Bool {
        var dict = readStorage()
        dict[key] = value
        return writeStorage(dict)
    }
    
    public func read(key: String) -> String? {
        let dict = readStorage()
        return dict[key]
    }
    
    @discardableResult
    public func delete(key: String) -> Bool {
        var dict = readStorage()
        if dict.removeValue(forKey: key) != nil {
            return writeStorage(dict)
        }
        return true
    }
}
