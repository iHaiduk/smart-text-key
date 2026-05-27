import AppKit
import SwiftUI

@MainActor
public final class StatusBarController: NSObject, NSWindowDelegate, StatusIndicatorProtocol {
    public static let shared = StatusBarController()
    
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    
    private override init() {
        super.init()
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Smart Text Key")
            image?.isTemplate = true
            button.image = image
            button.action = #selector(statusBarButtonClicked(_:))
            button.target = self
            // Intercept both left and right mouse up events on the status item
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        
        // Trigger context menu on right click or control-click
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu(sender)
        } else {
            openSettingsWindow()
        }
    }
    
    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        
        let activeConfig = AppSettings.shared.activeConfig
        let modelItem = NSMenuItem(title: "Active Model: \(activeConfig.modelName) (\(activeConfig.name))", action: nil, keyEquivalent: "")
        modelItem.isEnabled = false
        menu.addItem(modelItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Dynamic Prompt Actions Section
        let actions = AppSettings.shared.promptActions
        if !actions.isEmpty {
            let headerItem = NSMenuItem(title: "Run Action:", action: nil, keyEquivalent: "")
            headerItem.isEnabled = false
            menu.addItem(headerItem)
            
            for action in actions {
                let actionItem = NSMenuItem(
                    title: "  \(action.title)",
                    action: #selector(promptMenuItemClicked(_:)),
                    keyEquivalent: ""
                )
                actionItem.target = self
                actionItem.representedObject = action
                menu.addItem(actionItem)
            }
            
            menu.addItem(NSMenuItem.separator())
        }
        
        let quitItem = NSMenuItem(title: "Quit Smart Text Key", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: sender)
        }
    }
    
    @objc private func promptMenuItemClicked(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? PromptAction else { return }
        
        // Defer execution slightly to allow active app to reclaim keyboard focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Task {
                await ShortcutManager.shared.triggerAction(action)
            }
        }
    }
    
    @objc private func openSettingsFromMenu() {
        openSettingsWindow()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    public func openSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        
        // Premium modern resizable window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 530),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Smart Text Key Settings"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 800, height: 500)
        window.delegate = self
        
        self.settingsWindow = window
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func windowWillClose(_ notification: Notification) {
        self.settingsWindow = nil
    }
    
    public func setLoading(_ isLoading: Bool) {
        if let button = self.statusItem.button {
            let symbolName = isLoading ? "arrow.triangle.2.circlepath" : "character.bubble"
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Smart Text Key")
            image?.isTemplate = true
            button.image = image
            
            if isLoading {
                button.appearsDisabled = true
            } else {
                button.appearsDisabled = false
            }
        }
    }
}
