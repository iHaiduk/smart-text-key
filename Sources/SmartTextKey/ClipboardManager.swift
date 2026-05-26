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

    private enum Timing {
        static let modifierRelease: Duration = .milliseconds(150)
        static let copyTimeout: Duration = .milliseconds(400)
        static let pasteboardPoll: Duration = .milliseconds(20)
        static let sourceAppActivation: Duration = .milliseconds(200)
        static let pasteCompletion: Duration = .milliseconds(150)
    }

    private enum SelectionStrategy {
        case currentSelection
        case selectAll
    }

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
        sourceApplication = NSWorkspace.shared.frontmostApplication
        hadSelectionInitially = false

        // 1. Ensure Accessibility access
        guard checkAccessibilityPermissions(prompt: true) else {
            print("Smart Text Key: Missing Accessibility permissions.")
            return nil
        }

        // 2. Backup current clipboard content
        let backup = backupPasteboard()

        let pasteboard = NSPasteboard.general
        var capturedText = await captureText(from: pasteboard, using: .currentSelection)

        if Task.isCancelled { return nil }

        if hasMeaningfulText(capturedText) {
            hadSelectionInitially = true
        }

        // 4. Fallback Selection (Strategy 1):
        // If nothing is selected, fall back to Cmd+A to select all text in the active document.
        if !hasMeaningfulText(capturedText) {
            print("Smart Text Key: Selection empty. Falling back to Cmd+A (select all)...")
            usedSelectAll = true
            capturedText = await captureText(from: pasteboard, using: .selectAll)
            if Task.isCancelled { return nil }
        }

        guard let finalCaptured = capturedText, hasMeaningfulText(capturedText) else {
            print("Smart Text Key: Idle protection - No text selected, aborting flow.")
            // Restore previous clipboard content if no text was captured
            restorePasteboard(backup)
            return nil
        }

        return (text: finalCaptured, backup: backup)
    }

    /// Simulates Cmd+A to select all text in the active application.
    private func selectAll() async {
        simulateKeystroke(
            keyCode: CGKeyCode(kVK_ANSI_A),
            flags: .maskCommand
        )

        try? await Task.sleep(for: Timing.modifierRelease)
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
            try? await Task.sleep(for: Timing.sourceAppActivation)
        }

        // 2. Re-select the original text if needed.
        //    If the user had an initial selection, we do nothing (app preserves selection).
        //    If they did NOT have a selection, it means we selected everything (usedSelectAll was true).
        //    We trigger selectAll() again to ensure Cmd+V replaces everything.
        if !hadSelectionInitially && usedSelectAll {
            await selectAll()
        }

        // 3. Place the AI result on the clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 4. Simulate Cmd+V — this replaces the highlighted selection with the new text
        simulatePaste()

        // 5. Small delay (150ms) to let active application pull the text from the pasteboard
        try? await Task.sleep(for: Timing.pasteCompletion)

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

    private func captureText(from pasteboard: NSPasteboard, using strategy: SelectionStrategy) async -> String? {
        switch strategy {
        case .currentSelection:
            break
        case .selectAll:
            await selectAll()
        }

        pasteboard.clearContents()
        let changeCount = pasteboard.changeCount
        simulateCopy()
        return await waitForPasteboardString(on: pasteboard, after: changeCount)
    }

    private func waitForPasteboardString(on pasteboard: NSPasteboard, after changeCount: Int) async -> String? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Timing.copyTimeout)

        while clock.now < deadline {
            if pasteboard.changeCount != changeCount, let text = pasteboard.string(forType: .string) {
                return text
            }

            if Task.isCancelled {
                return nil
            }

            try? await Task.sleep(for: Timing.pasteboardPoll)
        }

        return pasteboard.string(forType: .string)
    }

    private func hasMeaningfulText(_ text: String?) -> Bool {
        guard let text else {
            return false
        }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
