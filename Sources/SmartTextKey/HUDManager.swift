import AppKit
import SwiftUI

// MARK: - Processing Capsule HUD View
struct ProcessingHUDView: View {
    @Bindable private var state = StreamingState.shared
    @Bindable private var settings = AppSettings.shared
    let actionTitle: String
    let modelName: String
    
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .scaleEffect(0.85)
            
            if state.isPreparing {
                if !state.shortcutName.isEmpty {
                    Text(state.shortcutName)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
                
                Text(actionTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            } else {
                Text(actionTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text("•")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.4))
                
                if state.isStreaming && state.tokenCount > 0 {
                    Text("Writing... \(state.tokenCount) tokens")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(settings.themeAccentColor)
                        .lineLimit(1)
                } else {
                    Text("Processing...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Text("•")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.4))
                
                Text(modelName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 400, height: 36)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
        .clipShape(Capsule())
    }
}

// MARK: - HUD Manager
@MainActor
public final class HUDManager {
    public static let shared = HUDManager()
    
    private var hudPanel: NSPanel?
    private var popoverPanel: NSPanel?
    
    private init() {}
    
    private func applyHUDTheme(to panel: NSPanel) {
        let theme = AppSettings.shared.hudTheme
        if theme == "dark" {
            panel.appearance = NSAppearance(named: .darkAqua)
        } else if theme == "light" {
            panel.appearance = NSAppearance(named: .aqua)
        } else {
            panel.appearance = nil // Inherit system standard
        }
    }
    
    /// Spawns a minimal horizontal capsule HUD at the bottom-center of the active screen.
    public func showHUD(actionTitle: String, modelName: String) {
        // Dismiss any existing HUD immediately without animations
        dismissHUD(animated: false)
        
        let hudView = ProcessingHUDView(actionTitle: actionTitle, modelName: modelName)
        let hostingController = NSHostingController(rootView: hudView)
        
        let hudWidth: CGFloat = 400
        let hudHeight: CGFloat = 36
        
        // 1. Calculate X & Y to position HUD at the bottom-center of the visible screen area (above dock)
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        
        let x = screenFrame.origin.x + (screenFrame.width - hudWidth) / 2
        let y = screenFrame.origin.y + 36 // 36 pt offset from screen bottom visible frame boundary
        
        let panelFrame = NSRect(x: x, y: y, width: hudWidth, height: hudHeight)
        
        // 2. Instantiate non-activating borderless NSPanel
        let panel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar // Floating above standard window objects
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.hasShadow = true
        applyHUDTheme(to: panel)
        
        self.hudPanel = panel
        
        // Animate smooth fade-in
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1.0
        }
    }
    
    /// Hides and destroys the capsule HUD with an elegant fade-out transition.
    public func dismissHUD(animated: Bool = true) {
        guard let panel = hudPanel else { return }
        self.hudPanel = nil
        
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
                    panel.orderOut(nil)
                }
            })
        } else {
            panel.orderOut(nil)
        }
    }
    
    /// Spawns the interactive borderless Popover HUD allowing preview and copy/paste confirmation.
    public func showPopover(
        resultText: String,
        promptTitle: String,
        onPaste: @escaping @MainActor () -> Void,
        onCopy: @escaping @MainActor () -> Void,
        onRegenerate: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        dismissPopover(animated: false)
        
        let popoverView = PopoverPreviewView(
            promptTitle: promptTitle,
            onPaste: { [weak self] in
                self?.dismissPopover()
                onPaste()
            },
            onCopy: { [weak self] in
                self?.dismissPopover()
                onCopy()
            },
            onRegenerate: { [weak self] in
                self?.dismissPopover()
                onRegenerate()
            },
            onCancel: { [weak self] in
                self?.dismissPopover()
                onCancel()
            }
        )
        
        let hostingController = NSHostingController(rootView: popoverView)
        
        let popoverWidth: CGFloat = 480
        let popoverHeight: CGFloat = 380
        
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        
        let x = screenFrame.origin.x + (screenFrame.width - popoverWidth) / 2
        let y = screenFrame.origin.y + 48
        
        let panelFrame = NSRect(x: x, y: y, width: popoverWidth, height: popoverHeight)
        
        let panel = InteractiveHUDPanel(
            contentRect: panelFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        panel.hasShadow = true
        applyHUDTheme(to: panel)
        
        self.popoverPanel = panel
        
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        
        // Force the panel to capture keyboard events immediately
        NSApp.activate(ignoringOtherApps: true)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1.0
        }
    }
    
    /// Hides and destroys the Popover HUD with a smooth fade-out.
    public func dismissPopover(animated: Bool = true) {
        guard let panel = popoverPanel else { return }
        self.popoverPanel = nil
        
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
                    panel.orderOut(nil)
                }
            })
        } else {
            panel.orderOut(nil)
        }
    }
}

// MARK: - Custom NSPanel subclass allowing borderless windows to receive focus/keys
class InteractiveHUDPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
}
