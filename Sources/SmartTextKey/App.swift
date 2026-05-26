import SwiftUI
import AppKit

@main
struct SmartTextKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Programmatically transform the app into a background-only accessory (no Dock icon, no main menu)
        NSApp.setActivationPolicy(.accessory)
        
        // 2. Initialize the Menu Bar Controller
        _ = StatusBarController.shared
        
        // 3. Register global keyboard shortcuts dynamically
        ShortcutManager.shared.registerAllShortcuts()
        
        // 4. Automatically show Settings window on initial start for easy configuration
        StatusBarController.shared.openSettingsWindow()
        
        print("Smart Text Key started successfully in background mode.")
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        print("Smart Text Key is terminating.")
    }
}
