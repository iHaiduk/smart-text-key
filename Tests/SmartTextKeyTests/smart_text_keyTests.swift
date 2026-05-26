import Testing
import Foundation
@testable import SmartTextKey

@Suite("SQLite History Database Tests")
@MainActor
struct HistoryDatabaseTests {
    
    @Test("Test logging, fetching, deleting, and clearing history database")
    func testDatabaseOperations() async throws {
        // Use a isolated in-memory database for testing to preserve production data
        HistoryManager.shared.useDatabase(at: ":memory:")
        
        // Start with a clean database
        HistoryManager.shared.clearAll()
        
        let initialItems = HistoryManager.shared.fetchAll()
        #expect(initialItems.isEmpty)
        
        // Log a couple of test transformations
        HistoryManager.shared.logTransformation(
            promptTitle: "Translate to English",
            inputText: "Привет, как дела?",
            outputText: "Hello, how are you?"
        )
        
        HistoryManager.shared.logTransformation(
            promptTitle: "Summarize Text",
            inputText: "Swift is a general-purpose, multi-paradigm, compiled programming language developed by Apple Inc. and the open-source community.",
            outputText: "Swift is a compiled programming language by Apple and open-source contributors."
        )
        
        // Fetch all items and verify count (newest should be first)
        let items = HistoryManager.shared.fetchAll()
        #expect(items.count == 2)
        
        // Verify order and contents
        #expect(items[0].promptTitle == "Summarize Text")
        #expect(items[0].inputText.contains("general-purpose"))
        #expect(items[0].outputText.contains("contributors"))
        
        #expect(items[1].promptTitle == "Translate to English")
        #expect(items[1].inputText == "Привет, как дела?")
        #expect(items[1].outputText == "Hello, how are you?")
        
        // Delete a single item
        let idToDelete = items[0].id
        HistoryManager.shared.delete(id: idToDelete)
        
        // Verify deletion of the first item
        let itemsAfterOneDelete = HistoryManager.shared.fetchAll()
        #expect(itemsAfterOneDelete.count == 1)
        #expect(itemsAfterOneDelete[0].id == items[1].id) // Only the translation item remains
        
        // Clear all history
        HistoryManager.shared.clearAll()
        
        // Verify database is completely empty
        let finalItems = HistoryManager.shared.fetchAll()
        #expect(finalItems.isEmpty)
    }
}

@Suite("Keychain Security Tests")
struct KeychainTests {
    
    @Test("Test saving, reading, and deleting secure keys from macOS Keychain")
    func testKeychainOperations() throws {
        let testKey = "com.smarttextkey.test.apikey"
        let testValue = "sk-proj-test123456789"
        
        // 1. Clean start
        KeychainHelper.shared.delete(key: testKey)
        #expect(KeychainHelper.shared.read(key: testKey) == nil)
        
        // 2. Save key
        let saved = KeychainHelper.shared.save(key: testKey, value: testValue)
        #expect(saved == true)
        
        // 3. Read key and check equality
        let retrieved = KeychainHelper.shared.read(key: testKey)
        #expect(retrieved == testValue)
        
        // 4. Delete key
        let deleted = KeychainHelper.shared.delete(key: testKey)
        #expect(deleted == true)
        
        // 5. Verify deleted
        #expect(KeychainHelper.shared.read(key: testKey) == nil)
    }
}
