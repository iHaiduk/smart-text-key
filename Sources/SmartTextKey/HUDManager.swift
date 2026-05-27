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
public final class HUDManager: HUDPresenterProtocol {
    public static let shared = HUDManager()
    
    private var hudPanel: NSPanel?
    private var popoverPanel: NSPanel?
    private var snippetsPanel: NSPanel?
    private var fixModePanel: NSPanel?
    
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
    
    private func makePanel<V: View>(contentView: V, width: CGFloat, height: CGFloat, screen: NSScreen?) -> NSPanel {
        let targetScreen = screen ?? NSScreen.screenWithMouse ?? NSScreen.main ?? NSScreen.screens.first
        guard let activeScreen = targetScreen else { return NSPanel() }
        let screenFrame = activeScreen.visibleFrame
        
        let panelOriginX = screenFrame.origin.x + (screenFrame.width - width) / 2
        let panelOriginY = screenFrame.origin.y + (screenFrame.height - height) / 2 + 100
        
        let hostingController = NSHostingController(rootView: contentView)
        
        let panel = InteractiveHUDPanel(
            contentRect: NSRect(x: panelOriginX, y: panelOriginY, width: width, height: height),
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
        
        return panel
    }
    
    private func showPanel(_ panel: NSPanel) {
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1.0
        }
    }
    
    /// Spawns a minimal horizontal capsule HUD at the bottom-center of the active screen.
    public func showHUD(actionTitle: String, modelName: String, screen: NSScreen?) {
        // Dismiss any existing HUD immediately without animations
        dismissHUD(animated: false)
        
        let hudView = ProcessingHUDView(actionTitle: actionTitle, modelName: modelName)
        let hostingController = NSHostingController(rootView: hudView)
        
        let hudWidth: CGFloat = 400
        let hudHeight: CGFloat = 36
        
        // 1. Calculate X & Y to position HUD at the bottom-center of the visible screen area (above dock)
        let targetScreen = screen ?? NSScreen.screenWithMouse ?? NSScreen.main ?? NSScreen.screens.first
        guard let activeScreen = targetScreen else { return }
        let screenFrame = activeScreen.visibleFrame
        
        let panelOriginX = screenFrame.origin.x + (screenFrame.width - hudWidth) / 2
        let panelOriginY = screenFrame.origin.y + 36 // 36 pt offset from screen bottom visible frame boundary
        
        let panelFrame = NSRect(x: panelOriginX, y: panelOriginY, width: hudWidth, height: hudHeight)
        
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
        screen: NSScreen?,
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
        
        let panel = makePanel(contentView: popoverView, width: 480, height: 380, screen: screen)
        self.popoverPanel = panel
        showPanel(panel)
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
    
    public func showSnippetsSearch(snippets: [PromptAction], onSelect: @escaping @MainActor (PromptAction) -> Void) {
        dismissSnippetsSearch()
        
        let overlayView = SnippetsSearchOverlayView(
            snippets: snippets,
            onSelect: { [weak self] snippet in
                self?.dismissSnippetsSearch()
                onSelect(snippet)
            },
            onCancel: { [weak self] in
                self?.dismissSnippetsSearch()
            }
        )
        
        let panel = makePanel(contentView: overlayView, width: 450, height: 350, screen: nil)
        self.snippetsPanel = panel
        showPanel(panel)
    }
    
    public func dismissSnippetsSearch() {
        guard let panel = snippetsPanel else { return }
        self.snippetsPanel = nil
        panel.orderOut(nil)
    }
    
    public func showFixModeInput(capturedText: String, onConfirm: @escaping @MainActor (String) -> Void, onCancel: @escaping @MainActor () -> Void) {
        dismissFixModeInput()
        
        let overlayView = FixModeInputOverlayView(
            capturedText: capturedText,
            onConfirm: { [weak self] instruction in
                self?.dismissFixModeInput()
                onConfirm(instruction)
            },
            onCancel: { [weak self] in
                self?.dismissFixModeInput()
                onCancel()
            }
        )
        
        let panel = makePanel(contentView: overlayView, width: 450, height: 260, screen: nil)
        self.fixModePanel = panel
        showPanel(panel)
    }
    
    public func dismissFixModeInput() {
        guard let panel = fixModePanel else { return }
        self.fixModePanel = nil
        panel.orderOut(nil)
    }
}

// MARK: - Custom NSPanel subclass allowing borderless windows to receive focus/keys
class InteractiveHUDPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
}

// MARK: - NSScreen Extension
extension NSScreen {
    public static var screenWithMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }
}
