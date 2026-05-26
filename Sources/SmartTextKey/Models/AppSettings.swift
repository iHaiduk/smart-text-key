import Foundation
import Observation
import SwiftUI
import ServiceManagement

@Observable
@MainActor
public final class AppSettings {
    public static let shared = AppSettings()

    private let userDefaults = UserDefaults.standard

    public var apiConfigs: [APIConfig] {
        didSet {
            saveAPIConfigs()
        }
    }

    public var activeConfigId: UUID {
        didSet {
            userDefaults.set(activeConfigId.uuidString, forKey: "activeConfigId")
        }
    }

    public var activeConfig: APIConfig {
        apiConfigs.first(where: { $0.id == activeConfigId }) ??
        apiConfigs.first ??
        APIConfig(name: "Local Ollama", apiBaseURL: "http://localhost:11434/v1", apiKey: "", modelName: "llama3")
    }

    public var promptActions: [PromptAction] {
        didSet {
            savePromptActions()
            ShortcutManager.shared.registerAllShortcuts()
        }
    }

    public var showPreviewPopover: Bool {
        didSet {
            userDefaults.set(showPreviewPopover, forKey: "showPreviewPopover")
        }
    }

    public var accentColor: String {
        didSet {
            userDefaults.set(accentColor, forKey: "accentColor")
        }
    }

    public var hudTheme: String {
        didSet {
            userDefaults.set(hudTheme, forKey: "hudTheme")
        }
    }

    public var enableSoundEffects: Bool {
        didSet {
            userDefaults.set(enableSoundEffects, forKey: "enableSoundEffects")
        }
    }

    public var launchAtLoginError: String? = nil

    public var launchAtLogin: Bool {
        didSet {
            userDefaults.set(launchAtLogin, forKey: "launchAtLogin")
            let service = SMAppService.mainApp
            do {
                if launchAtLogin {
                    try service.register()
                } else {
                    try service.unregister()
                }
                launchAtLoginError = nil
            } catch {
                let errorMsg = "Failed to \(launchAtLogin ? "enable" : "disable") launch at login: \(error.localizedDescription)"
                print("Smart Text Key [AppSettings]: \(errorMsg)")
                launchAtLoginError = errorMsg
            }
        }
    }

    public var databaseDiagnosticError: String? {
        HistoryManager.shared.databaseError
    }

    public var themeAccentColor: SwiftUI.Color {
        switch accentColor {
        case "blue": return .blue
        case "emerald": return .green
        case "amber": return .orange
        case "graphite": return .gray
        default: return .purple
        }
    }

    private init() {
        // 1. Declare local variables for the loading phase to satisfy Swift's strict initialization rules
        let loadedApiConfigs: [APIConfig]
        let loadedActiveConfigId: UUID
        let loadedPromptActions: [PromptAction]
        let loadedShowPreviewPopover: Bool
        let loadedAccentColor: String
        let loadedHudTheme: String
        let loadedEnableSoundEffects: Bool
        let loadedLaunchAtLogin: Bool

        let defaults = UserDefaults.standard

        // 2. Load API Configurations
        if let data = defaults.data(forKey: "apiConfigs"),
           let decoded = try? JSONDecoder().decode([APIConfig].self, from: data) {
            loadedApiConfigs = decoded
        } else {
            // Default configured endpoints: Local Ollama & OpenAI Cloud
            let localOllama = APIConfig(
                name: "Local Ollama",
                apiBaseURL: APIProvider.ollama.defaultBaseURL,
                apiKey: "",
                modelName: APIProvider.ollama.defaultModelName,
                providerId: APIProvider.ollama.id
            )
            let openaiCloud = APIConfig(
                name: "OpenAI Cloud",
                apiBaseURL: APIProvider.openAICompatible.defaultBaseURL,
                apiKey: "",
                modelName: APIProvider.openAICompatible.defaultModelName,
                providerId: APIProvider.openAICompatible.id
            )
            let defaultConfigs = [localOllama, openaiCloud]
            loadedApiConfigs = defaultConfigs

            if let data = try? JSONEncoder().encode(defaultConfigs) {
                defaults.set(data, forKey: "apiConfigs")
            }
        }

        // 3. Load Active Configuration ID
        if let idString = defaults.string(forKey: "activeConfigId"),
           let uuid = UUID(uuidString: idString) {
            loadedActiveConfigId = uuid
        } else {
            let defaultId = loadedApiConfigs.first?.id ?? UUID()
            loadedActiveConfigId = defaultId
            defaults.set(defaultId.uuidString, forKey: "activeConfigId")
        }

        // 4. Load Prompt Actions
        if let data = defaults.data(forKey: "promptActions"),
           let decoded = try? JSONDecoder().decode([PromptAction].self, from: data) {
            loadedPromptActions = decoded
        } else {
            // Default template actions
            let defaultActions = [
                PromptAction(
                    title: "Refactoring",
                    systemPrompt: "You are an expert software engineer. Refactor and clean up the provided code. Output only the improved code inside standard formatting without preamble.",
                    template: "Refactor the following code:\n\n{{TEXT}}",
                    shortcutId: "refactoring"
                ),
                PromptAction(
                    title: "Translate to RU",
                    systemPrompt: "You are a professional translator. Translate the text into natural Russian.",
                    template: "{{TEXT}}",
                    shortcutId: "translate_ru"
                )
            ]
            loadedPromptActions = defaultActions

            // Initial save
            if let data = try? JSONEncoder().encode(defaultActions) {
                defaults.set(data, forKey: "promptActions")
            }
        }

        // 5. Load Show Preview Popover toggle
        loadedShowPreviewPopover = defaults.bool(forKey: "showPreviewPopover")

        // 6. Load premium bundle settings
        loadedAccentColor = defaults.string(forKey: "accentColor") ?? "purple"
        loadedHudTheme = defaults.string(forKey: "hudTheme") ?? "system"
        loadedEnableSoundEffects = defaults.object(forKey: "enableSoundEffects") as? Bool ?? true
        loadedLaunchAtLogin = defaults.bool(forKey: "launchAtLogin")

        // 7. Assign loaded values to stored properties to complete phase 1 of Swift initialization
        self.apiConfigs = loadedApiConfigs
        self.activeConfigId = loadedActiveConfigId
        self.promptActions = loadedPromptActions
        self.showPreviewPopover = loadedShowPreviewPopover
        self.accentColor = loadedAccentColor
        self.hudTheme = loadedHudTheme
        self.enableSoundEffects = loadedEnableSoundEffects
        self.launchAtLogin = loadedLaunchAtLogin
    }

    private func saveAPIConfigs() {
        if let data = try? JSONEncoder().encode(apiConfigs) {
            userDefaults.set(data, forKey: "apiConfigs")
        }
    }

    private func savePromptActions() {
        if let data = try? JSONEncoder().encode(promptActions) {
            userDefaults.set(data, forKey: "promptActions")
        }
    }
}
