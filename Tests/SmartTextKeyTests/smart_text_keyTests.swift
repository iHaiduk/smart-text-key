import Testing
import Foundation
import AppKit
@testable import SmartTextKey

@Suite("SQLite History Database Tests", .serialized)
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
            outputText: "Hello, how are you?",
            modelName: "gpt-4o"
        )
        
        HistoryManager.shared.logTransformation(
            promptTitle: "Summarize Text",
            inputText: "Swift is a general-purpose, multi-paradigm, compiled programming language developed by Apple Inc. and the open-source community.",
            outputText: "Swift is a compiled programming language by Apple and open-source contributors.",
            modelName: "gpt-4o"
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

@Suite("Keychain Security Tests", .serialized)
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

@Suite("Prompt Action Response Suffix Tests", .serialized)
struct PromptActionTests {
    @Test("Test prompt action response suffix is correctly stored and accessed")
    func testResponseSuffixStoring() async throws {
        let action = PromptAction(
            title: "Test Action",
            systemPrompt: "You are a test helper.",
            template: "{{TEXT}}",
            shortcutId: "test_action",
            responseSuffix: "\n\nSuffix Added!"
        )
        
        #expect(action.responseSuffix == "\n\nSuffix Added!")
        
        let actionWithoutSuffix = PromptAction(
            title: "Test Action 2",
            systemPrompt: "You are a test helper.",
            template: "{{TEXT}}",
            shortcutId: "test_action_2"
        )
        #expect(actionWithoutSuffix.responseSuffix == nil)
    }
}

// MARK: - Pipeline Mock Implementation Support

@MainActor
final class MockClipboardClient: ClipboardClientProtocol {
    var sourceApplication: NSRunningApplication? = nil
    var hadSelectionInitially = true
    var usedSelectAll = false
    
    var capturedText = "Initial selection text"
    var backupData: [NSPasteboard.PasteboardType: Data] = [.string: "Original clipboard data".data(using: .utf8)!]
    var originalClipboardText = "Original clipboard data"
    
    var captureCalled = false
    var pasteCalled = false
    var restoreCalled = false
    
    var pastedText: String? = nil
    var restoredBackup: [NSPasteboard.PasteboardType: Data]? = nil
    
    func captureSelectedText() async -> (text: String, backup: [NSPasteboard.PasteboardType: Data], originalClipboardText: String)? {
        captureCalled = true
        return (text: capturedText, backup: backupData, originalClipboardText: originalClipboardText)
    }
    
    func pasteResultText(_ text: String, originalBackup: [NSPasteboard.PasteboardType: Data], sourceApplication: NSRunningApplication?) async {
        pasteCalled = true
        pastedText = text
    }
    
    func restorePasteboard(_ backup: [NSPasteboard.PasteboardType: Data]) {
        restoreCalled = true
        restoredBackup = backup
    }
    
    func backupPasteboard() -> [NSPasteboard.PasteboardType: Data] {
        return backupData
    }
    
    func resetState() {
        sourceApplication = nil
        hadSelectionInitially = false
        usedSelectAll = false
    }
}

@MainActor
final class MockAIClient: AIClientProtocol {
    var processCalled = false
    var responseText = "AI processed text"
    var shouldFail = false
    var failureError: Error = NSError(domain: "MockAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "AI connection failed"])
    
    var lastCapturedText: String? = nil
    var lastOriginalClipboardText: String? = nil
    var lastAction: PromptAction? = nil
    
    func process(
        action: PromptAction,
        capturedText: String,
        originalClipboardText: String,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        processCalled = true
        lastAction = action
        lastCapturedText = capturedText
        lastOriginalClipboardText = originalClipboardText
        
        if shouldFail {
            throw failureError
        }
        
        onChunk?(responseText)
        return responseText
    }
}

@MainActor
final class MockHUDPresenter: HUDPresenterProtocol {
    var showHUDCalled = false
    var dismissHUDCalled = false
    var showPopoverCalled = false
    var dismissPopoverCalled = false
    
    var lastHUDTitle: String? = nil
    var lastHUDModel: String? = nil
    var lastPopoverTitle: String? = nil
    
    var onPasteCallback: (() -> Void)? = nil
    var onCopyCallback: (() -> Void)? = nil
    var onRegenerateCallback: (() -> Void)? = nil
    var onCancelCallback: (() -> Void)? = nil
    
    func showHUD(actionTitle: String, modelName: String, screen: NSScreen?) {
        showHUDCalled = true
        lastHUDTitle = actionTitle
        lastHUDModel = modelName
    }
    
    func dismissHUD(animated: Bool) {
        dismissHUDCalled = true
    }
    
    func showPopover(
        resultText: String,
        promptTitle: String,
        screen: NSScreen?,
        onPaste: @escaping @MainActor () -> Void,
        onCopy: @escaping @MainActor () -> Void,
        onRegenerate: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        showPopoverCalled = true
        lastPopoverTitle = promptTitle
        onPasteCallback = onPaste
        onCopyCallback = onCopy
        onRegenerateCallback = onRegenerate
        onCancelCallback = onCancel
    }
    
    func dismissPopover(animated: Bool) {
        dismissPopoverCalled = true
    }
    
    func showSnippetsSearch(snippets: [PromptAction], onSelect: @escaping @MainActor (PromptAction) -> Void) {}
    func dismissSnippetsSearch() {}
    func showFixModeInput(capturedText: String, onConfirm: @escaping @MainActor (String) -> Void, onCancel: @escaping @MainActor () -> Void) {}
    func dismissFixModeInput() {}
}

@MainActor
final class MockHistoryStore: HistoryStoreProtocol {
    var logCalled = false
    var lastPromptTitle: String? = nil
    var lastInputText: String? = nil
    var lastOutputText: String? = nil
    var lastModelName: String? = nil
    
    func logTransformation(promptTitle: String, inputText: String, outputText: String, modelName: String) {
        logCalled = true
        lastPromptTitle = promptTitle
        lastInputText = inputText
        lastOutputText = outputText
        lastModelName = modelName
    }
}

@MainActor
final class MockErrorReporter: ErrorReporterProtocol {
    var reportCalled = false
    var lastTitle: String? = nil
    var lastMessage: String? = nil

    func reportError(title: String, message: String) {
        reportCalled = true
        lastTitle = title
        lastMessage = message
    }
}

final class MockSoundPlayer: SoundPlayerProtocol {
    func play(_ type: SoundManager.SoundType) {}
}

@MainActor
final class MockStatusIndicator: StatusIndicatorProtocol {
    private(set) var loadingStates: [Bool] = []

    func setLoading(_ isLoading: Bool) {
        loadingStates.append(isLoading)
    }
}

@Suite("Text Transformation Pipeline Tests", .serialized)
@MainActor
struct TransformationPipelineTests {
    
    @Test("Test pipeline direct HUD paste succeeds and substitutes template")
    func testPipelineDirectHUDSuccess() async throws {
        let clipboard = MockClipboardClient()
        let ai = MockAIClient()
        let hud = MockHUDPresenter()
        let history = MockHistoryStore()
        let reporter = MockErrorReporter()
        let soundPlayer = MockSoundPlayer()
        let statusIndicator = MockStatusIndicator()
        
        let pipeline = TransformationPipeline(
            clipboardClient: clipboard,
            aiClient: ai,
            hudPresenter: hud,
            historyStore: history,
            errorReporter: reporter,
            soundPlayer: soundPlayer,
            statusIndicator: statusIndicator
        )
        
        let action = PromptAction(
            title: "Summarize",
            systemPrompt: "Summarize this text",
            template: "Summarize: {{TEXT}}\nOriginal Clipboard: {{CLIPBOARD}}",
            shortcutId: "summarize"
        )
        
        // Force showPreviewPopover to false for direct HUD paste
        AppSettings.shared.showPreviewPopover = false
        
        await pipeline.run(action: action)
        
        #expect(clipboard.captureCalled == true)
        #expect(ai.processCalled == true)
        #expect(ai.lastCapturedText == "Initial selection text")
        #expect(ai.lastOriginalClipboardText == "Original clipboard data")
        
        #expect(hud.showHUDCalled == true)
        #expect(hud.dismissHUDCalled == true)
        
        #expect(clipboard.pasteCalled == true)
        #expect(clipboard.pastedText == "AI processed text")
        
        #expect(history.logCalled == true)
        #expect(history.lastPromptTitle == "Summarize")
        #expect(history.lastInputText == "Initial selection text")
        #expect(history.lastOutputText == "AI processed text")
        #expect(reporter.reportCalled == false)
    }
    
    @Test("Test pipeline fallback occurs when primary AI client fails")
    func testPipelinePrimaryFailWithFallback() async throws {
        let clipboard = MockClipboardClient()
        let ai = MockAIClient()
        let hud = MockHUDPresenter()
        let history = MockHistoryStore()
        let reporter = MockErrorReporter()
        let soundPlayer = MockSoundPlayer()
        let statusIndicator = MockStatusIndicator()
        
        ai.shouldFail = true
        
        let pipeline = TransformationPipeline(
            clipboardClient: clipboard,
            aiClient: ai,
            hudPresenter: hud,
            historyStore: history,
            errorReporter: reporter,
            soundPlayer: soundPlayer,
            statusIndicator: statusIndicator
        )
        
        let action = PromptAction(
            title: "Translate",
            systemPrompt: "Translate text",
            template: "{{TEXT}}",
            shortcutId: "translate"
        )
        
        AppSettings.shared.showPreviewPopover = false
        
        await pipeline.run(action: action)
        
        // Pipeline should fail and restore the original clipboard
        #expect(clipboard.captureCalled == true)
        #expect(ai.processCalled == true)
        #expect(clipboard.restoreCalled == true)
        #expect(clipboard.pasteCalled == false)
        #expect(history.logCalled == false)
        #expect(reporter.reportCalled == true)
        #expect(reporter.lastMessage?.contains("AI connection failed") == true)
    }
    
    @Test("Test empty response does not overwrite clipboard")
    func testPipelineEmptyResponseHandling() async throws {
        let clipboard = MockClipboardClient()
        let ai = MockAIClient()
        let hud = MockHUDPresenter()
        let history = MockHistoryStore()
        let reporter = MockErrorReporter()
        let soundPlayer = MockSoundPlayer()
        let statusIndicator = MockStatusIndicator()
        
        ai.responseText = "" // Empty response
        
        let pipeline = TransformationPipeline(
            clipboardClient: clipboard,
            aiClient: ai,
            hudPresenter: hud,
            historyStore: history,
            errorReporter: reporter,
            soundPlayer: soundPlayer,
            statusIndicator: statusIndicator
        )
        
        let action = PromptAction(
            title: "Rewrite",
            systemPrompt: "Rewrite text",
            template: "{{TEXT}}",
            shortcutId: "rewrite"
        )
        
        AppSettings.shared.showPreviewPopover = false
        
        await pipeline.run(action: action)
        
        #expect(clipboard.captureCalled == true)
        #expect(ai.processCalled == true)
        
        // Output should not be pasted, clipboard must be restored
        #expect(clipboard.pasteCalled == false)
        #expect(clipboard.restoreCalled == true)
        #expect(history.logCalled == false)
        #expect(reporter.reportCalled == true)
        #expect(reporter.lastMessage?.contains("empty response") == true)
    }
    
    @Test("Test pipeline bypasses selection capture when pre-captured text and backup are provided")
    func testPipelineBypassesCaptureWithPreCapturedInput() async throws {
        let clipboard = MockClipboardClient()
        let ai = MockAIClient()
        let hud = MockHUDPresenter()
        let history = MockHistoryStore()
        let reporter = MockErrorReporter()
        let soundPlayer = MockSoundPlayer()
        let statusIndicator = MockStatusIndicator()
        
        let pipeline = TransformationPipeline(
            clipboardClient: clipboard,
            aiClient: ai,
            hudPresenter: hud,
            historyStore: history,
            errorReporter: reporter,
            soundPlayer: soundPlayer,
            statusIndicator: statusIndicator
        )
        
        let action = PromptAction(
            title: "Summarize",
            systemPrompt: "Summarize this text",
            template: "Summarize: {{TEXT}}\nOriginal Clipboard: {{CLIPBOARD}}",
            shortcutId: "summarize"
        )
        
        AppSettings.shared.showPreviewPopover = false
        
        let preCapturedBackup: [NSPasteboard.PasteboardType: Data] = [.string: "Pre-captured backup data".data(using: .utf8)!]
        
        await pipeline.run(
            action: action,
            preCapturedText: "Pre-captured text content",
            preCapturedBackup: preCapturedBackup,
            originalClipboardText: "Original pre-captured clipboard"
        )
        
        #expect(clipboard.captureCalled == false) // Bypassed!
        #expect(ai.processCalled == true)
        #expect(ai.lastCapturedText == "Pre-captured text content")
        #expect(ai.lastOriginalClipboardText == "Original pre-captured clipboard")
        
        #expect(hud.showHUDCalled == true)
        #expect(hud.dismissHUDCalled == true)
        
        #expect(clipboard.pasteCalled == true)
        #expect(clipboard.pastedText == "AI processed text")
        
        #expect(history.logCalled == true)
        #expect(history.lastPromptTitle == "Summarize")
        #expect(history.lastInputText == "Pre-captured text content")
        #expect(history.lastOutputText == "AI processed text")
        #expect(reporter.reportCalled == false)
    }
}
