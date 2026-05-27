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
    private struct CaptureResult {
        let text: String
        let backup: [NSPasteboard.PasteboardType: Data]
        let originalClipboardText: String
    }

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

        guard await waitForModifiersRelease() else {
            cancelRun()
            return
        }

        if await handleSnippetAction(action, sourceApplication: sourceApplication) {
            return
        }

        soundPlayer.play(.start)
        state = .capturingText

        guard let result = await captureResult(
            preCapturedText: preCapturedText,
            preCapturedBackup: preCapturedBackup,
            originalClipboardText: originalClipboardText
        ) else {
            state = .idle
            return
        }

        let context = makeContext(
            sourceApplication: sourceApplication ?? clipboardClient.sourceApplication,
            originalClipboardText: result.originalClipboardText
        )

        if Task.isCancelled {
            clipboardClient.restorePasteboard(result.backup)
            state = .cancelled(context: context)
            state = .idle
            return
        }
        statusIndicator.setLoading(true)
        StreamingState.shared.reset()
        let modelName = resolveModelName(for: action)
        prepareStreamingState(for: action)
        state = .preparingGeneration(capturedText: result.text, context: context)

        if settings.showPreviewPopover {
            await executePreviewProcessing(action: action, result: result, context: context, modelName: modelName)
            state = .idle
            return
        }

        await executeDirectProcessing(action: action, result: result, context: context, modelName: modelName)
        statusIndicator.setLoading(false)
        hudPresenter.dismissHUD(animated: true)
        state = .idle
    }

    private func waitForModifiersRelease() async -> Bool {
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 1.0 {
            let activeModifierFlags = currentModifierFlags()
            let modifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            if activeModifierFlags.isDisjoint(with: modifierMask) {
                break
            }

            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                return false
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(50))
        } catch {
            return false
        }

        return !Task.isCancelled
    }

    private func cancelRun() {
        state = .cancelled(context: PipelineContext())
    }

    private func handleSnippetAction(
        _ action: PromptAction,
        sourceApplication: NSRunningApplication?
    ) async -> Bool {
        guard action.isSnippet else {
            return false
        }

        let dateString = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        let clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
        let frontmostApplication = currentFrontmostApplication(fallback: sourceApplication)
        let applicationName = frontmostApplication?.localizedName ?? "Active App"

        var textToPaste = action.template
        textToPaste = textToPaste.replacingOccurrences(of: "{{CLIPBOARD}}", with: clipboardText)
        textToPaste = textToPaste.replacingOccurrences(of: "{{DATE}}", with: dateString)
        textToPaste = textToPaste.replacingOccurrences(of: "{{CURRENT_APP}}", with: applicationName)

        soundPlayer.play(.success)
        let backup = clipboardClient.backupPasteboard()
        await clipboardClient.pasteResultText(
            textToPaste,
            originalBackup: backup,
            sourceApplication: frontmostApplication
        )

        state = .completed(
            outputText: textToPaste,
            context: PipelineContext(sourceApplication: frontmostApplication)
        )
        state = .idle
        return true
    }

    private func captureResult(
        preCapturedText: String?,
        preCapturedBackup: [NSPasteboard.PasteboardType: Data]?,
        originalClipboardText: String?
    ) async -> CaptureResult? {
        if let preCapturedText, let preCapturedBackup {
            return CaptureResult(
                text: preCapturedText,
                backup: preCapturedBackup,
                originalClipboardText: originalClipboardText ?? ""
            )
        }

        guard let capture = await clipboardClient.captureSelectedText() else {
            return nil
        }

        return CaptureResult(
            text: capture.text,
            backup: capture.backup,
            originalClipboardText: capture.originalClipboardText
        )
    }

    private func makeContext(
        sourceApplication: NSRunningApplication?,
        originalClipboardText: String
    ) -> PipelineContext {
        PipelineContext(
            sourceApplication: sourceApplication,
            activeScreen: currentScreenWithMouse(),
            mouseLocation: currentMouseLocation(),
            originalClipboardText: originalClipboardText
        )
    }

    private func currentModifierFlags() -> NSEvent.ModifierFlags {
        guard NSApp != nil else {
            return []
        }

        return NSEvent.modifierFlags
    }

    private func currentFrontmostApplication(fallback: NSRunningApplication?) -> NSRunningApplication? {
        guard NSApp != nil else {
            return fallback
        }

        return fallback ?? NSWorkspace.shared.frontmostApplication
    }

    private func currentScreenWithMouse() -> NSScreen? {
        guard NSApp != nil else {
            return nil
        }

        return NSScreen.screenWithMouse
    }

    private func currentMouseLocation() -> NSPoint {
        guard NSApp != nil else {
            return .zero
        }

        return NSEvent.mouseLocation
    }

    private func resolveModelName(for action: PromptAction) -> String {
        if let boundId = action.apiConfigId,
           let boundConfig = settings.apiConfigs.first(where: { $0.id == boundId }) {
            return boundConfig.modelName
        }

        return settings.activeConfig.modelName
    }

    private func prepareStreamingState(for action: PromptAction) {
        let shortcutName = KeyboardShortcuts.Name(action.shortcutId)
        StreamingState.shared.shortcutName = KeyboardShortcuts.getShortcut(for: shortcutName)?.description ?? ""
        StreamingState.shared.isPreparing = true
        StreamingState.shared.isStreaming = true

        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                StreamingState.shared.isPreparing = false
            }
        }
    }

    private func executePreviewProcessing(
        action: PromptAction,
        result: CaptureResult,
        context: PipelineContext,
        modelName: String
    ) async {
        hudPresenter.showPopover(
            resultText: "",
            promptTitle: action.title,
            screen: context.activeScreen,
            onPaste: { [weak self] in
                guard let self else { return }
                Task {
                    let text = StreamingState.shared.text
                    await self.clipboardClient.pasteResultText(
                        text,
                        originalBackup: result.backup,
                        sourceApplication: context.sourceApplication
                    )
                    self.state = .idle
                }
            },
            onCopy: { [weak self] in
                guard let self else { return }
                let text = StreamingState.shared.text
                let pasteboard = NSPasteboard.general
                pasteboard.declareTypes([.string], owner: nil)
                pasteboard.setString(text, forType: .string)
                self.state = .idle
            },
            onRegenerate: { [weak self] in
                guard let self else { return }
                self.state = .idle
                Task {
                    await self.run(action: action)
                }
            },
            onCancel: { [weak self] in
                guard let self else { return }
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
    }

    private func executeDirectProcessing(
        action: PromptAction,
        result: CaptureResult,
        context: PipelineContext,
        modelName: String
    ) async {
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
                guard let self else { return }
                await self.clipboardClient.pasteResultText(
                    response,
                    originalBackup: result.backup,
                    sourceApplication: context.sourceApplication
                )
            }
        )
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
