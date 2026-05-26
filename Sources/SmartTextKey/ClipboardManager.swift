import AppKit
import Carbon
import ApplicationServices

@MainActor
public final class ClipboardManager {
    public static let shared = ClipboardManager()
    
    /// Tracks the application that was focused when text capture started,
    /// so we can re-activate it before pasting the AI result back.
    private(set) var sourceApplication: NSRunningApplication?
    
    /// Tracks whether `Cmd+A` (select-all) was used during the last capture,
    /// so the paste flow knows to re-select with the same strategy.
    private(set) var usedSelectAll = false
    
    /// Tracks whether the text was captured from an existing user selection.
    private(set) var hadSelectionInitially = false
    
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
        // 0. Remember which app the user is working in so we can re-activate it before paste
        sourceApplication = NSWorkspace.shared.frontmostApplication
        usedSelectAll = false
        hadSelectionInitially = false
        
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
            restorePasteboard(backup)
            return nil
        }
        
        // 6. Read pasteboard content
        var capturedText = pasteboard.string(forType: .string)
        
        if let text = capturedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hadSelectionInitially = true
        }
        
        // 6b. Smart Caret-to-Start Selection (Strategy 1):
        // If nothing is selected, try Cmd+Shift+Up to select from the very beginning
        // of the focused input up to the current cursor (caret) position.
        if capturedText == nil || capturedText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("Smart Text Key: Selection empty. Strategy 1: Cmd+Shift+Up (select to start of field)...")
            await growSelectionToCaret()
            
            // Re-simulate Cmd+C
            pasteboard.clearContents()
            simulateCopy()
            
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                restorePasteboard(backup)
                return nil
            }
            
            capturedText = pasteboard.string(forType: .string)
        }
        
        // 6c. Fallback Selection (Strategy 2):
        // If Cmd+Shift+Up didn't work (custom editors like SnippetsLab),
        // fall back to Cmd+A which is universally supported.
        if capturedText == nil || capturedText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("Smart Text Key: Strategy 1 failed. Strategy 2: Cmd+A (select all)...")
            await selectAll()
            usedSelectAll = true
            
            // Re-simulate Cmd+C
            pasteboard.clearContents()
            simulateCopy()
            
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                restorePasteboard(backup)
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
    
    /// Simulates a macOS keyboard shortcut to select all text from the very beginning
    /// of the focused input field up to the current cursor (caret) position.
    ///
    /// Uses Cmd+Shift+Up Arrow which is the universal macOS text system binding
    /// for "move to beginning of document and modify selection". This works in both
    /// single-line text fields and multi-line text areas across standard Cocoa,
    /// Electron, and browser-based text inputs.
    ///
    /// The operation is intentionally "soft" — it only fires when no text is currently
    /// selected, so it does not interfere with keyboard shortcuts or override an
    /// existing user selection.
    private func growSelectionToCaret() async {
        // Select from current caret position to the very start of the text field:
        // Cmd + Shift + Up Arrow (moveToBeginningOfDocumentAndModifySelection:)
        simulateKeystroke(
            keyCode: CGKeyCode(kVK_UpArrow),
            flags: [.maskCommand, .maskShift]
        )
        
        do {
            try await Task.sleep(nanoseconds: 50_000_000)
        } catch {}
    }
    
    /// Universal fallback: simulates Cmd+A to select all text in the focused field.
    /// Works in virtually every macOS application including custom code editors.
    private func selectAll() async {
        simulateKeystroke(
            keyCode: CGKeyCode(kVK_ANSI_A),
            flags: .maskCommand
        )
        
        do {
            try await Task.sleep(nanoseconds: 50_000_000)
        } catch {}
    }
    
    /// Writes the result to the clipboard, re-activates the source application,
    /// re-selects the original text, simulates a Cmd+V paste (replacing the selection),
    /// and restores original clipboard contents.
    public func pasteResultText(_ text: String, originalBackup: [NSPasteboard.PasteboardType: Data]) async {
        // 1. Re-activate the source application that was focused during capture.
        //    This is critical because the popover/HUD may have stolen focus.
        if let sourceApp = sourceApplication {
            sourceApp.activate()
            
            // Give the target app time to regain focus and keyboard input
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {}
        }
        
        // 2. Re-select the original text so that Cmd+V *replaces* it instead of inserting.
        //    If the user had an initial selection, we don't simulate any selection key strokes
        //    since the target app preserves their active selection upon reactivation.
        if hadSelectionInitially {
            // Do nothing, the active selection is already preserved in the reactivated app.
        } else if usedSelectAll {
            await selectAll()
        } else {
            await growSelectionToCaret()
        }
        
        // 3. Place the AI result on the clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // 4. Simulate Cmd+V — this replaces the highlighted selection with the new text
        simulatePaste()
        
        // 5. Small delay (150ms) to let active application pull the text from the pasteboard
        do {
            try await Task.sleep(nanoseconds: 150_000_000)
        } catch {}
        
        // 6. Restore user's original clipboard content
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
