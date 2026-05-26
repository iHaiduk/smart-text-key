import AppKit
import Carbon
import ApplicationServices

@MainActor
public final class ClipboardManager {
    public static let shared = ClipboardManager()
    
    private init() {}
    
    /// Checks whether accessibility permissions are granted. If not and `prompt` is true, triggers macOS native system dialog.
    public func checkAccessibilityPermissions(prompt: Bool = true) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    /// Safely captures selected text using a simulated Cmd+C keystroke.
    /// Returns a tuple containing the captured text and the backup dictionary of the clipboard before capture.
    /// Returns nil if permissions are missing or no text was selected (aborted).
    public func captureSelectedText() async -> (text: String, backup: [NSPasteboard.PasteboardType: Data])? {
        // 1. Ensure Accessibility access
        guard checkAccessibilityPermissions(prompt: true) else {
            print("Smart Text Key: Missing Accessibility permissions.")
            return nil
        }
        
        // 2. Backup current clipboard content
        let backup = backupPasteboard()
        
        // 3. Clear pasteboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // 4. Simulate Cmd+C
        simulateCopy()
        
        // 5. Short sleep (100ms) to allow target application to process Cmd+C and update general pasteboard
        do {
            try await Task.sleep(nanoseconds: 100_000_000)
        } catch {
            return nil
        }
        
        // 6. Read pasteboard content
        var capturedText = pasteboard.string(forType: .string)
        
        // 6b. Smart Paragraph Selection Growth:
        // If nothing is selected, we attempt to expand the selection to the active paragraph automatically.
        if capturedText == nil || capturedText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("Smart Text Key: Selection empty. Attempting smart paragraph selection growth...")
            await growSelectionToParagraph()
            
            // Re-simulate Cmd+C
            pasteboard.clearContents()
            simulateCopy()
            
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return nil
            }
            
            capturedText = pasteboard.string(forType: .string)
        }
        
        guard let finalCaptured = capturedText, !finalCaptured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("Smart Text Key: Idle protection - No text selected, aborting flow.")
            // Restore previous clipboard content if no text was captured
            restorePasteboard(backup)
            return nil
        }
        
        return (text: finalCaptured, backup: backup)
    }
    
    /// Simulates macOS keyboard macro to expand cursor focus to select the active paragraph.
    private func growSelectionToParagraph() async {
        // Move cursor to start of paragraph: Option + Up Arrow
        simulateKeystroke(keyCode: CGKeyCode(kVK_UpArrow), flags: .maskAlternate)
        
        do {
            try await Task.sleep(nanoseconds: 30_000_000)
        } catch {}
        
        // Select from cursor to end of paragraph: Option + Shift + Down Arrow
        simulateKeystroke(keyCode: CGKeyCode(kVK_DownArrow), flags: [.maskAlternate, .maskShift])
        
        do {
            try await Task.sleep(nanoseconds: 40_000_000)
        } catch {}
    }
    
    /// Writes the result to the clipboard, simulates a Cmd+V paste, and restores original clipboard contents.
    public func pasteResultText(_ text: String, originalBackup: [NSPasteboard.PasteboardType: Data]) async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Simulate Cmd+V
        simulatePaste()
        
        // Small delay (150ms) to let active application pull the text from the pasteboard before restoring original backup
        do {
            try await Task.sleep(nanoseconds: 150_000_000)
        } catch {}
        
        // Restore user's original clipboard content
        restorePasteboard(originalBackup)
    }
    
    // MARK: - Clipboard Backup & Restore Helpers
    
    public func backupPasteboard() -> [NSPasteboard.PasteboardType: Data] {
        let pasteboard = NSPasteboard.general
        var backedUpData: [NSPasteboard.PasteboardType: Data] = [:]
        if let types = pasteboard.types {
            for type in types {
                if let data = pasteboard.data(forType: type) {
                    backedUpData[type] = data
                }
            }
        }
        return backedUpData
    }
    
    public func restorePasteboard(_ backup: [NSPasteboard.PasteboardType: Data]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for (type, data) in backup {
            pasteboard.setData(data, forType: type)
        }
    }
    
    // MARK: - Event Simulations (CGEvent)
    
    private func simulateCopy() {
        simulateKeystroke(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
    }
    
    private func simulatePaste() {
        simulateKeystroke(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }
    
    private func simulateKeystroke(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.post(tap: .cghidEventTap)
    }
}
