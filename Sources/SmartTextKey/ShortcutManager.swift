import AppKit
import KeyboardShortcuts

@MainActor
public final class ShortcutManager {
    public static let shared = ShortcutManager()
    
    private var activeTask: Task<Void, Never>?
    private var globalEscapeMonitor: Any?
    private var localEscapeMonitor: Any?
    
    private let pipeline = TransformationPipeline()
    private var registeredShortcutIds = Set<String>()
    
    private init() {}
    
    /// Safely terminates any currently executing generation task and releases references.
    public func cancelActiveTask() {
        if let task = activeTask {
            AppLogger.shortcut.log("Cancelling existing active generation task...")
            task.cancel()
            activeTask = nil
        }
    }
    
    /// Public entrypoint to run an action pipeline with cancellation support and Escape key monitoring.
    public func triggerAction(
        _ action: PromptAction,
        preCapturedText: String? = nil,
        preCapturedBackup: [NSPasteboard.PasteboardType: Data]? = nil,
        originalClipboardText: String? = nil,
        sourceApplication: NSRunningApplication? = nil
    ) async {
        cancelActiveTask()
        
        // Register global and local monitors for Escape key (53) during streaming
        self.globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                AppLogger.shortcut.log("Escape key pressed globally. Cancelling active task...")
                self?.cancelActiveTask()
            }
        }
        
        self.localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                AppLogger.shortcut.log("Escape key pressed locally. Cancelling active task...")
                self?.cancelActiveTask()
                return nil // consume event
            }
            return event
        }
        
        self.activeTask = Task {
            defer {
                if let monitor = self.globalEscapeMonitor {
                    NSEvent.removeMonitor(monitor)
                    self.globalEscapeMonitor = nil
                }
                if let monitor = self.localEscapeMonitor {
                    NSEvent.removeMonitor(monitor)
                    self.localEscapeMonitor = nil
                }
            }
            await self.pipeline.run(
                action: action,
                preCapturedText: preCapturedText,
                preCapturedBackup: preCapturedBackup,
                originalClipboardText: originalClipboardText,
                sourceApplication: sourceApplication
            )
        }
        
        _ = await self.activeTask?.result
    }
    
    /// Registers keyup observers for all configured PromptActions dynamically.
    /// Overwrites existing observers for the same shortcutId keys automatically.
    public func registerAllShortcuts() {
        let actions = AppSettings.shared.promptActions
        let currentIds = Set(actions.map { $0.shortcutId })
        
        // 1. Unregister and reset deleted/obsolete shortcuts
        let removedIds = registeredShortcutIds.subtracting(currentIds)
        for id in removedIds {
            let name = KeyboardShortcuts.Name(id)
            KeyboardShortcuts.disable(name)
            KeyboardShortcuts.reset(name) // Clears it from UserDefaults
            AppLogger.shortcut.log("Unregistered and cleared obsolete shortcut: \(id)")
        }
        
        // 2. Clear all legacy observers from KeyboardShortcuts
        KeyboardShortcuts.removeAllHandlers()
        
        AppLogger.shortcut.log("Re-registering \(actions.count) global hotkeys...")
        
        registeredShortcutIds = currentIds
        
        // 3. Register handlers for current actions
        for action in actions {
            let name = KeyboardShortcuts.Name(action.shortcutId)
            
            KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
                guard let self = self else { return }
                let targetApp = NSWorkspace.shared.frontmostApplication
                Task {
                    let matchingActions = AppSettings.shared.promptActions.filter { $0.shortcutId == action.shortcutId }
                    let activeBundleId = targetApp?.bundleIdentifier
                    
                    let resolved: PromptAction
                    if let appSpecific = matchingActions.first(where: { $0.bundleId == activeBundleId }) {
                        resolved = appSpecific
                    } else if let global = matchingActions.first(where: { $0.bundleId == nil }) {
                        resolved = global
                    } else {
                        resolved = action
                    }
                    
                    await self.triggerAction(resolved, sourceApplication: targetApp)
                }
            }
        }
        
        // 4. Register system handlers
        KeyboardShortcuts.onKeyUp(for: .snippetsSearch) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.showSnippetsSearchOverlay()
            }
        }
        
        KeyboardShortcuts.onKeyUp(for: .fixMode) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                await self.triggerFixModeFlow()
            }
        }
    }
    
    public func showSnippetsSearchOverlay() {
        let snippets = AppSettings.shared.promptActions.filter { $0.isSnippet }
        guard !snippets.isEmpty else {
            AlertErrorReporter.shared.reportError(
                title: "No Snippets Configured",
                message: "Please open Settings, create or select an Action, and tick 'Is Text Snippet' to configure snippets."
            )
            return
        }
        
        let targetApp = NSWorkspace.shared.frontmostApplication
        
        HUDManager.shared.showSnippetsSearch(snippets: snippets) { [weak self] selectedSnippet in
            guard let self = self else { return }
            Task {
                await self.triggerAction(selectedSnippet, sourceApplication: targetApp)
            }
        }
    }
    
    public func triggerFixModeFlow() async {
        cancelActiveTask()
        
        let targetApp = NSWorkspace.shared.frontmostApplication
        
        // 1. Capture selected text
        guard let result = await ClipboardManager.shared.captureSelectedText() else {
            return
        }
        
        // 2. Open Fix Mode Input Panel
        HUDManager.shared.showFixModeInput(capturedText: result.text, onConfirm: { [weak self] instruction in
            guard let self = self else { return }
            
            // Build a dynamic action
            let fixAction = PromptAction(
                title: "Fix Mode: \(instruction)",
                systemPrompt: "You are an AI text editing assistant. Modify the provided text strictly according to the instruction. Return ONLY the modified text. Do NOT add any preamble, markdown code blocks, explanations, or notes.",
                template: "Instruction: \(instruction)\n\nText to modify:\n{{TEXT}}",
                shortcutId: "fix_mode_dynamic"
            )
            
            Task {
                await self.triggerAction(
                    fixAction,
                    preCapturedText: result.text,
                    preCapturedBackup: result.backup,
                    originalClipboardText: result.originalClipboardText,
                    sourceApplication: targetApp
                )
            }
        }, onCancel: {
            ClipboardManager.shared.restorePasteboard(result.backup)
        })
    }
}
