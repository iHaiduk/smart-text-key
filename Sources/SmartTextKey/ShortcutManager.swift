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
            print("Smart Text Key: Cancelling existing active generation task...")
            task.cancel()
            activeTask = nil
        }
    }
    
    /// Public entrypoint to run an action pipeline with cancellation support and Escape key monitoring.
    public func triggerAction(_ action: PromptAction) async {
        cancelActiveTask()
        
        // Register global and local monitors for Escape key (53) during streaming
        self.globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                print("Smart Text Key: Escape key pressed globally. Cancelling active task...")
                self?.cancelActiveTask()
            }
        }
        
        self.localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                print("Smart Text Key: Escape key pressed locally. Cancelling active task...")
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
            await self.pipeline.run(action: action)
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
            print("Smart Text Key: Unregistered and cleared obsolete shortcut: \(id)")
        }
        
        // 2. Clear all legacy observers from KeyboardShortcuts
        KeyboardShortcuts.removeAllHandlers()
        
        print("Smart Text Key: Re-registering \(actions.count) global hotkeys...")
        
        registeredShortcutIds = currentIds
        
        // 3. Register handlers for current actions
        for action in actions {
            let name = KeyboardShortcuts.Name(action.shortcutId)
            
            KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
                guard let self = self else { return }
                Task {
                    await self.triggerAction(action)
                }
            }
        }
    }
}
