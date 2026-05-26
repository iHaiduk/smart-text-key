import AppKit
import KeyboardShortcuts

@MainActor
public final class ShortcutManager {
    public static let shared = ShortcutManager()
    
    private var activeTask: Task<Void, Never>?
    private var globalEscapeMonitor: Any?
    private var localEscapeMonitor: Any?
    
    private init() {}
    
    /// Safely terminates any currently executing generation task and releases references.
    public func cancelActiveTask() {
        if let task = activeTask {
            print("Smart Text Key: Cancelling existing active generation task...")
            task.cancel()
            activeTask = nil
        }
    }
    
    /// Registers keyup observers for all configured PromptActions dynamically.
    /// Overwrites existing observers for the same shortcutId keys automatically.
    public func registerAllShortcuts() {
        let actions = AppSettings.shared.promptActions
        print("Smart Text Key: Re-registering \(actions.count) global hotkeys...")
        
        for action in actions {
            let name = KeyboardShortcuts.Name(action.shortcutId)
            
            KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
                guard let self = self else { return }
                self.cancelActiveTask()
                self.activeTask = Task {
                    await self.triggerAction(action)
                }
            }
        }
    }
    
    /// Orchestrates the safe capture, AI generation, and simulated insertion pipeline.
    func triggerAction(_ action: PromptAction) async {
        print("Smart Text Key: Global hotkey triggered for action: [\(action.title)]")
        
        // Wait up to 1 second to ensure user has released hotkey modifier keys
        // (e.g. Cmd, Shift, Option) so they don't collide with simulated keystrokes.
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 1.0 {
            let flags = NSEvent.modifierFlags
            let mask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            if flags.intersection(mask).isEmpty {
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        
        // Add a tiny extra delay to let the OS clear the state
        try? await Task.sleep(for: .milliseconds(50))
        
        if Task.isCancelled {
            print("Smart Text Key: Task cancelled during initial delay.")
            return
        }
        
        // Clean up Escape monitors automatically when triggerAction completes or is cancelled
        defer {
            if let monitor = globalEscapeMonitor {
                NSEvent.removeMonitor(monitor)
                globalEscapeMonitor = nil
            }
            if let monitor = localEscapeMonitor {
                NSEvent.removeMonitor(monitor)
                localEscapeMonitor = nil
            }
        }
        
        // Play audio start sound cue
        SoundManager.shared.play(.start)
        
        // 1. Safely capture text with idle protection and automatic selection growth check
        guard let result = await ClipboardManager.shared.captureSelectedText() else {
            // Safe exit (e.g. no text selected, clipboard untouched)
            return
        }
        
        let capturedText = result.text
        let backup = result.backup
        
        // Return early if task has been cancelled before request starts
        if Task.isCancelled {
            ClipboardManager.shared.restorePasteboard(backup)
            return
        }
        
        // Register global and local monitors for Escape key (53) during streaming
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                print("Smart Text Key: Escape key pressed globally. Cancelling active task...")
                self?.cancelActiveTask()
            }
        }
        
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                print("Smart Text Key: Escape key pressed locally. Cancelling active task...")
                self?.cancelActiveTask()
                return nil // consume event
            }
            return event
        }
        
        print("Smart Text Key: Captured \(capturedText.count) characters. Activating AI pipeline...")
        
        // 2. Set Menu Bar icon and prepare streaming state
        StatusBarController.shared.setLoading(true)
        
        // Reset streaming state on main actor
        StreamingState.shared.reset()
        
        let apiSettings = AppSettings.shared
        let modelName: String
        if let boundId = action.apiConfigId,
           let boundConfig = apiSettings.apiConfigs.first(where: { $0.id == boundId }) {
            modelName = boundConfig.modelName
        } else {
            modelName = apiSettings.activeConfig.modelName
        }
        
        let shortcutName = KeyboardShortcuts.Name(action.shortcutId)
        if let shortcut = KeyboardShortcuts.getShortcut(for: shortcutName) {
            StreamingState.shared.shortcutName = shortcut.description
        } else {
            StreamingState.shared.shortcutName = ""
        }
        StreamingState.shared.isPreparing = true
        StreamingState.shared.isStreaming = true
        
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run { StreamingState.shared.isPreparing = false }
        }
        
        var shouldCleanHUDAtEnd = true
        
        if AppSettings.shared.showPreviewPopover {
            shouldCleanHUDAtEnd = false
            
            // Show interactive popover immediately so user can watch streaming in real time
            HUDManager.shared.showPopover(
                resultText: "",
                promptTitle: action.title,
                onPaste: {
                    Task {
                        let text = StreamingState.shared.text
                        await ClipboardManager.shared.pasteResultText(text, originalBackup: backup)
                    }
                },
                onCopy: {
                    let text = StreamingState.shared.text
                    let pasteboard = NSPasteboard.general
                    pasteboard.declareTypes([.string], owner: nil)
                    pasteboard.setString(text, forType: .string)
                },
                onRegenerate: { [weak self] in
                    guard let self = self else { return }
                    self.cancelActiveTask()
                    self.activeTask = Task {
                        await self.triggerAction(action)
                    }
                },
                onCancel: { [weak self] in
                    guard let self = self else { return }
                    self.cancelActiveTask()
                    ClipboardManager.shared.restorePasteboard(backup)
                }
            )
            
            do {
                let response = try await AIService.shared.process(action: action, capturedText: capturedText) { chunk in
                    // Terminate chunks if task was cancelled mid-stream
                    guard !Task.isCancelled else { return }
                    Task { @MainActor in
                        StreamingState.shared.text += chunk
                        StreamingState.shared.tokenCount += 1
                    }
                }
                
                // Double check cancellation before completing
                if Task.isCancelled {
                    throw CancellationError()
                }
                
                let cleanResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanResponse.isEmpty else {
                    throw NSError(domain: "SmartTextKey", code: -1, userInfo: [NSLocalizedDescriptionKey: "AI returned an empty response. Text was not replaced."])
                }
                
                print("Smart Text Key: AI stream completed successfully.")
                StreamingState.shared.isStreaming = false
                StreamingState.shared.text = response
                
                // Log transformation in local SQLite database
                HistoryManager.shared.logTransformation(
                    promptTitle: action.title,
                    inputText: capturedText,
                    outputText: response,
                    modelName: modelName
                )
                
                // Play audio success sound cue
                SoundManager.shared.play(.success)
                
            } catch {
                StreamingState.shared.isStreaming = false
                
                if error is CancellationError || Task.isCancelled {
                    print("Smart Text Key: Generation task was cooperativesly cancelled.")
                    ClipboardManager.shared.restorePasteboard(backup)
                    HUDManager.shared.dismissPopover(animated: false)
                    StatusBarController.shared.setLoading(false)
                    return
                }
                
                print("Smart Text Key: Error processing action: \(error.localizedDescription)")
                SoundManager.shared.play(.failure)
                
                // Restore original clipboard contents on error
                ClipboardManager.shared.restorePasteboard(backup)
                HUDManager.shared.dismissPopover(animated: false)
                StatusBarController.shared.setLoading(false)
                
                showErrorAlert(
                    title: "Action Execution Failed",
                    message: "Could not execute action '\(action.title)'.\n\nReason: \(error.localizedDescription)"
                )
            }
        } else {
            // Non-popover mode: show horizontal progress capsule HUD
            HUDManager.shared.showHUD(actionTitle: action.title, modelName: modelName)
            
            do {
                let response = try await AIService.shared.process(action: action, capturedText: capturedText) { chunk in
                    guard !Task.isCancelled else { return }
                    Task { @MainActor in
                        StreamingState.shared.text += chunk
                        StreamingState.shared.tokenCount += 1
                    }
                }
                
                if Task.isCancelled {
                    throw CancellationError()
                }
                
                let cleanResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanResponse.isEmpty else {
                    throw NSError(domain: "SmartTextKey", code: -1, userInfo: [NSLocalizedDescriptionKey: "AI returned an empty response. Text was not replaced."])
                }
                
                print("Smart Text Key: AI request completed successfully. Simulating direct paste...")
                StreamingState.shared.isStreaming = false
                
                // Paste response and restore user's original clipboard
                await ClipboardManager.shared.pasteResultText(response, originalBackup: backup)
                
                // Log transformation in local SQLite database
                HistoryManager.shared.logTransformation(
                    promptTitle: action.title,
                    inputText: capturedText,
                    outputText: response,
                    modelName: modelName
                )
                
                // Play audio success sound cue
                SoundManager.shared.play(.success)
                
            } catch {
                StreamingState.shared.isStreaming = false
                
                if error is CancellationError || Task.isCancelled {
                    print("Smart Text Key: HUD generation task was cooperativesly cancelled.")
                    ClipboardManager.shared.restorePasteboard(backup)
                    HUDManager.shared.dismissHUD(animated: false)
                    StatusBarController.shared.setLoading(false)
                    return
                }
                
                print("Smart Text Key: Error processing action: \(error.localizedDescription)")
                SoundManager.shared.play(.failure)
                
                // Restore original clipboard contents on error
                ClipboardManager.shared.restorePasteboard(backup)
                HUDManager.shared.dismissHUD(animated: false)
                StatusBarController.shared.setLoading(false)
                
                showErrorAlert(
                    title: "Action Execution Failed",
                    message: "Could not execute action '\(action.title)'.\n\nReason: \(error.localizedDescription)"
                )
            }
        }
        
        // 5. Restore Menu Bar icon and dismiss progress HUD smoothly if needed
        if shouldCleanHUDAtEnd {
            StatusBarController.shared.setLoading(false)
            HUDManager.shared.dismissHUD()
        }
    }
    
    /// Displays a standard modal warning alert inside the active thread.
    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        
        // Bring app to foreground momentarily to show the alert, then yield focus
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
