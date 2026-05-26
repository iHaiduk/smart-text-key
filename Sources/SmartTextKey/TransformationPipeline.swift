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
    
    public private(set) var state: PipelineState = .idle {
        didSet {
            print("Smart Text Key [Pipeline]: State changed to \(state)")
        }
    }
    
    public init(
        clipboardClient: ClipboardClientProtocol = ClipboardManager.shared,
        aiClient: AIClientProtocol = AIService.shared,
        hudPresenter: HUDPresenterProtocol = HUDManager.shared,
        historyStore: HistoryStoreProtocol = HistoryManager.shared,
        errorReporter: ErrorReporterProtocol = AlertErrorReporter.shared
    ) {
        self.clipboardClient = clipboardClient
        self.aiClient = aiClient
        self.hudPresenter = hudPresenter
        self.historyStore = historyStore
        self.errorReporter = errorReporter
    }
    
    /// Starts the pipeline orchestration for a given PromptAction.
    public func run(action: PromptAction) async {
        guard state == .idle else {
            print("Smart Text Key [Pipeline]: Pipeline is already running!")
            return
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
        
        // Play start sound cue
        SoundManager.shared.play(.start)
        
        state = .capturingText
        
        // 2. Capture selected text
        guard let result = await clipboardClient.captureSelectedText() else {
            state = .idle
            return
        }
        
        let context = PipelineContext(
            sourceApplication: clipboardClient.sourceApplication,
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
        StatusBarController.shared.setLoading(true)
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
        
        state = .preparingGeneration(capturedText: result.text, context: context)
        
        var shouldCleanHUDAtEnd = true
        
        if AppSettings.shared.showPreviewPopover {
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
            
            do {
                state = .streaming(capturedText: result.text, context: context)
                
                let response = try await aiClient.process(
                    action: action,
                    capturedText: result.text,
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
                StreamingState.shared.text = response
                
                historyStore.logTransformation(
                    promptTitle: action.title,
                    inputText: result.text,
                    outputText: response,
                    modelName: modelName
                )
                
                SoundManager.shared.play(.success)
                state = .completed(outputText: response, context: context)
                
            } catch {
                StreamingState.shared.isStreaming = false
                
                if error is CancellationError || Task.isCancelled {
                    clipboardClient.restorePasteboard(result.backup)
                    hudPresenter.dismissPopover(animated: false)
                    StatusBarController.shared.setLoading(false)
                    state = .cancelled(context: context)
                    state = .idle
                    return
                }
                
                SoundManager.shared.play(.failure)
                clipboardClient.restorePasteboard(result.backup)
                hudPresenter.dismissPopover(animated: false)
                StatusBarController.shared.setLoading(false)
                
                state = .error(error.localizedDescription, context: context)
                errorReporter.reportError(
                    title: "Action Execution Failed",
                    message: "Could not execute action '\(action.title)'.\n\nReason: \(error.localizedDescription)"
                )
                state = .idle
            }
        } else {
            // Non-popover mode: direct HUD paste
            hudPresenter.showHUD(actionTitle: action.title, modelName: modelName, screen: context.activeScreen)
            
            do {
                state = .streaming(capturedText: result.text, context: context)
                
                let response = try await aiClient.process(
                    action: action,
                    capturedText: result.text,
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
                
                await clipboardClient.pasteResultText(response, originalBackup: result.backup, sourceApplication: context.sourceApplication)
                
                historyStore.logTransformation(
                    promptTitle: action.title,
                    inputText: result.text,
                    outputText: response,
                    modelName: modelName
                )
                
                SoundManager.shared.play(.success)
                state = .completed(outputText: response, context: context)
                
            } catch {
                StreamingState.shared.isStreaming = false
                
                if error is CancellationError || Task.isCancelled {
                    clipboardClient.restorePasteboard(result.backup)
                    hudPresenter.dismissHUD(animated: false)
                    StatusBarController.shared.setLoading(false)
                    state = .cancelled(context: context)
                    state = .idle
                    return
                }
                
                SoundManager.shared.play(.failure)
                clipboardClient.restorePasteboard(result.backup)
                hudPresenter.dismissHUD(animated: false)
                StatusBarController.shared.setLoading(false)
                
                state = .error(error.localizedDescription, context: context)
                errorReporter.reportError(
                    title: "Action Execution Failed",
                    message: "Could not execute action '\(action.title)'.\n\nReason: \(error.localizedDescription)"
                )
                state = .idle
            }
        }
        
        if shouldCleanHUDAtEnd {
            StatusBarController.shared.setLoading(false)
            hudPresenter.dismissHUD(animated: true)
        }
        
        state = .idle
    }
}
