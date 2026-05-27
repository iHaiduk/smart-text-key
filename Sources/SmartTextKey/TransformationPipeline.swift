import AppKit
import KeyboardShortcuts

public struct PipelineContext {
    public let sourceApplication: NSRunningApplication?
    public let activeScreen: NSScreen?
    public let mouseLocation: NSPoint
    public let originalClipboardText: String
    
    public init(
        sourceApplication: NSRunningApplication? = nil,
        activeScreen: NSScreen? = nil,
        mouseLocation: NSPoint = .zero,
        originalClipboardText: String = ""
    ) {
        self.sourceApplication = sourceApplication
        self.activeScreen = activeScreen
        self.mouseLocation = mouseLocation
        self.originalClipboardText = originalClipboardText
    }
}

public enum PipelineState: Equatable, CustomStringConvertible {
    case idle
    case waitingForModifiersRelease
    case capturingText
    case preparingGeneration(capturedText: String, context: PipelineContext)
    case streaming(capturedText: String, context: PipelineContext)
    case completed(outputText: String, context: PipelineContext)
    case error(String, context: PipelineContext)
    case cancelled(context: PipelineContext)
    
    public var description: String {
        switch self {
        case .idle: return "Idle"
        case .waitingForModifiersRelease: return "Waiting for Modifiers Release"
        case .capturingText: return "Capturing Selected Text"
        case .preparingGeneration: return "Preparing AI Generation"
        case .streaming: return "Streaming Response"
        case .completed: return "Completed Successfully"
        case .error(let errorMsg, _): return "Failed with error: \(errorMsg)"
        case .cancelled: return "Cancelled"
        }
    }
    
    public static func == (lhs: PipelineState, rhs: PipelineState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.waitingForModifiersRelease, .waitingForModifiersRelease): return true
        case (.capturingText, .capturingText): return true
        case (.preparingGeneration(let t1, _), .preparingGeneration(let t2, _)): return t1 == t2
        case (.streaming(let t1, _), .streaming(let t2, _)): return t1 == t2
        case (.completed(let t1, _), .completed(let t2, _)): return t1 == t2
        case (.error(let e1, _), .error(let e2, _)): return e1 == e2
        case (.cancelled, .cancelled): return true
        default: return false
        }
    }
}

@MainActor
public final class TransformationPipeline {
    private let clipboardClient: ClipboardClientProtocol
    private let aiClient: AIClientProtocol
    private let hudPresenter: HUDPresenterProtocol
    private let historyStore: HistoryStoreProtocol
    private let errorReporter: ErrorReporterProtocol
    private let soundPlayer: SoundPlayerProtocol
    private let statusIndicator: StatusIndicatorProtocol
    private let settings: AppSettings
    
    public private(set) var state: PipelineState = .idle {
        didSet {
            AppLogger.pipeline.log("State changed to \(self.state)")
        }
    }
    
    public init(
        clipboardClient: ClipboardClientProtocol = ClipboardManager.shared,
        aiClient: AIClientProtocol = AIService.shared,
        hudPresenter: HUDPresenterProtocol = HUDManager.shared,
        historyStore: HistoryStoreProtocol = HistoryManager.shared,
        errorReporter: ErrorReporterProtocol = AlertErrorReporter.shared,
        soundPlayer: SoundPlayerProtocol = SoundManager.shared,
        statusIndicator: StatusIndicatorProtocol = StatusBarController.shared,
        settings: AppSettings = AppSettings.shared
    ) {
        self.clipboardClient = clipboardClient
        self.aiClient = aiClient
        self.hudPresenter = hudPresenter
        self.historyStore = historyStore
        self.errorReporter = errorReporter
        self.soundPlayer = soundPlayer
        self.statusIndicator = statusIndicator
        self.settings = settings
    }
    
    /// Starts the pipeline orchestration for a given PromptAction.
    public func run(
        action: PromptAction,
        preCapturedText: String? = nil,
        preCapturedBackup: [NSPasteboard.PasteboardType: Data]? = nil,
        originalClipboardText: String? = nil,
        sourceApplication: NSRunningApplication? = nil
    ) async {
        guard state == .idle else {
            AppLogger.pipeline.warning("Pipeline is already running!")
            return
        }
        
        if preCapturedText == nil {
            clipboardClient.resetState()
        }
        
        state = .waitingForModifiersRelease
        
        // 1. Wait for modifier keys to be released to prevent collision with simulated keys
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 1.0 {
            let flags = NSEvent.modifierFlags
            let mask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            if flags.intersection(mask).isEmpty {
                break
            }
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                state = .cancelled(context: PipelineContext())
                return
            }
        }
        
        do {
            try await Task.sleep(for: .milliseconds(50))
        } catch {
            state = .cancelled(context: PipelineContext())
            return
        }
        
        if Task.isCancelled {
            state = .cancelled(context: PipelineContext())
            return
        }
        
        if action.isSnippet {
            let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
            let originalClipboard = NSPasteboard.general.string(forType: .string) ?? ""
            let appName = (sourceApplication ?? NSWorkspace.shared.frontmostApplication)?.localizedName ?? "Active App"
            
            var textToPaste = action.template
            textToPaste = textToPaste.replacingOccurrences(of: "{{CLIPBOARD}}", with: originalClipboard)
            textToPaste = textToPaste.replacingOccurrences(of: "{{DATE}}", with: dateStr)
            textToPaste = textToPaste.replacingOccurrences(of: "{{CURRENT_APP}}", with: appName)
            
            soundPlayer.play(.success)
            let backup = clipboardClient.backupPasteboard()
            let frontApp = sourceApplication ?? NSWorkspace.shared.frontmostApplication
            
            await clipboardClient.pasteResultText(textToPaste, originalBackup: backup, sourceApplication: frontApp)
            
            state = .completed(outputText: textToPaste, context: PipelineContext(sourceApplication: frontApp))
            state = .idle
            return
        }
        
        // Play start sound cue
        soundPlayer.play(.start)
        
        state = .capturingText
        
        struct CaptureResult {
            let text: String
            let backup: [NSPasteboard.PasteboardType: Data]
            let originalClipboardText: String
        }
        
        let result: CaptureResult
        if let preCapturedText = preCapturedText, let preCapturedBackup = preCapturedBackup {
            result = CaptureResult(
                text: preCapturedText,
                backup: preCapturedBackup,
                originalClipboardText: originalClipboardText ?? ""
            )
        } else {
            guard let capture = await clipboardClient.captureSelectedText() else {
                state = .idle
                return
            }
            result = CaptureResult(
                text: capture.text,
                backup: capture.backup,
                originalClipboardText: capture.originalClipboardText
            )
        }
        
        let context = PipelineContext(
            sourceApplication: sourceApplication ?? clipboardClient.sourceApplication,
            activeScreen: NSScreen.screenWithMouse,
            mouseLocation: NSEvent.mouseLocation,
            originalClipboardText: result.originalClipboardText
        )
        
        if Task.isCancelled {
            clipboardClient.restorePasteboard(result.backup)
            state = .cancelled(context: context)
            state = .idle
            return
        }
        
        // 3. Prepare AI pipeline
        statusIndicator.setLoading(true)
        StreamingState.shared.reset()
        
        let apiSettings = settings
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
        
        state = .preparingGeneration(capturedText: result.text, context: context)
        
        var shouldCleanHUDAtEnd = true
        
        if settings.showPreviewPopover {
            shouldCleanHUDAtEnd = false
            
            hudPresenter.showPopover(
                resultText: "",
                promptTitle: action.title,
                screen: context.activeScreen,
                onPaste: { [weak self] in
                    guard let self = self else { return }
                    Task {
                        let text = StreamingState.shared.text
                        await self.clipboardClient.pasteResultText(text, originalBackup: result.backup, sourceApplication: context.sourceApplication)
                        self.state = .idle
                    }
                },
                onCopy: { [weak self] in
                    guard let self = self else { return }
                    let text = StreamingState.shared.text
                    let pasteboard = NSPasteboard.general
                    pasteboard.declareTypes([.string], owner: nil)
                    pasteboard.setString(text, forType: .string)
                    self.state = .idle
                },
                onRegenerate: { [weak self] in
                    guard let self = self else { return }
                    self.state = .idle
                    // Trigger regeneration by starting the pipeline again
                    Task {
                        await self.run(action: action)
                    }
                },
                onCancel: { [weak self] in
                    guard let self = self else { return }
                    self.clipboardClient.restorePasteboard(result.backup)
                    self.state = .cancelled(context: context)
                    self.state = .idle
                }
            )
            
            await executeProcessing(
                action: action,
                capturedText: result.text,
                backup: result.backup,
                context: context,
                modelName: modelName,
                dismissUI: { [weak self] animated in
                    self?.hudPresenter.dismissPopover(animated: animated)
                },
                onSuccess: { response in
                    StreamingState.shared.text = response
                }
            )
        } else {
            // Non-popover mode: direct HUD paste
            hudPresenter.showHUD(actionTitle: action.title, modelName: modelName, screen: context.activeScreen)
            
            await executeProcessing(
                action: action,
                capturedText: result.text,
                backup: result.backup,
                context: context,
                modelName: modelName,
                dismissUI: { [weak self] animated in
                    self?.hudPresenter.dismissHUD(animated: animated)
                },
                onSuccess: { [weak self] response in
                    guard let self = self else { return }
                    await self.clipboardClient.pasteResultText(response, originalBackup: result.backup, sourceApplication: context.sourceApplication)
                }
            )
        }
        
        if shouldCleanHUDAtEnd {
            statusIndicator.setLoading(false)
            hudPresenter.dismissHUD(animated: true)
        }
        
        state = .idle
    }

    private func executeProcessing(
        action: PromptAction,
        capturedText: String,
        backup: [NSPasteboard.PasteboardType: Data],
        context: PipelineContext,
        modelName: String,
        dismissUI: @MainActor @escaping (Bool) -> Void,
        onSuccess: @MainActor @escaping (String) async -> Void
    ) async {
        do {
            state = .streaming(capturedText: capturedText, context: context)
            
            let response = try await aiClient.process(
                action: action,
                capturedText: capturedText,
                originalClipboardText: context.originalClipboardText
            ) { chunk in
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
            
            StreamingState.shared.isStreaming = false
            
            await onSuccess(response)
            
            historyStore.logTransformation(
                promptTitle: action.title,
                inputText: capturedText,
                outputText: response,
                modelName: modelName
            )
            
            soundPlayer.play(.success)
            state = .completed(outputText: response, context: context)
            
        } catch {
            StreamingState.shared.isStreaming = false
            
            if error is CancellationError || Task.isCancelled {
                clipboardClient.restorePasteboard(backup)
                dismissUI(false)
                statusIndicator.setLoading(false)
                state = .cancelled(context: context)
                state = .idle
                return
            }
            
            soundPlayer.play(.failure)
            clipboardClient.restorePasteboard(backup)
            dismissUI(false)
            statusIndicator.setLoading(false)
            
            state = .error(error.localizedDescription, context: context)
            errorReporter.reportError(
                title: "Action Execution Failed",
                message: "Could not execute action '\(action.title)'.\n\nReason: \(error.localizedDescription)"
            )
            state = .idle
        }
    }
}
