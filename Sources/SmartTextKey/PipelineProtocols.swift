import AppKit

@MainActor
public protocol ClipboardClientProtocol {
    var sourceApplication: NSRunningApplication? { get }
    var hadSelectionInitially: Bool { get }
    var usedSelectAll: Bool { get }
    
    func captureSelectedText() async -> (text: String, backup: [NSPasteboard.PasteboardType: Data], originalClipboardText: String)?
    func pasteResultText(_ text: String, originalBackup: [NSPasteboard.PasteboardType: Data], sourceApplication: NSRunningApplication?) async
    func restorePasteboard(_ backup: [NSPasteboard.PasteboardType: Data])
}

@MainActor
public protocol AIClientProtocol {
    func process(
        action: PromptAction,
        capturedText: String,
        originalClipboardText: String,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String
}

@MainActor
public protocol HUDPresenterProtocol {
    func showHUD(actionTitle: String, modelName: String, screen: NSScreen?)
    func dismissHUD(animated: Bool)
    func showPopover(
        resultText: String,
        promptTitle: String,
        screen: NSScreen?,
        onPaste: @escaping @MainActor () -> Void,
        onCopy: @escaping @MainActor () -> Void,
        onRegenerate: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    )
    func dismissPopover(animated: Bool)
}

@MainActor
public protocol HistoryStoreProtocol {
    func logTransformation(promptTitle: String, inputText: String, outputText: String, modelName: String)
}

@MainActor
public protocol ErrorReporterProtocol {
    func reportError(title: String, message: String)
}

@MainActor
public final class AlertErrorReporter: ErrorReporterProtocol {
    public static let shared = AlertErrorReporter()
    private init() {}

    public func reportError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
