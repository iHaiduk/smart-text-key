import SwiftUI
import Observation
import KeyboardShortcuts

public struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var selectedTab: Selection = .apiSettings
    
    enum Selection: Hashable {
        case apiSettings
        case history
        case action(UUID)
    }
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar
            VStack(alignment: .leading, spacing: 16) {
                // App Brand Header
                HStack(spacing: 12) {
                    Image(systemName: "character.bubble")
                        .font(.system(size: 24))
                        .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Text Key")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.1")")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // Sidebar items
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("GLOBAL")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        
                        // API Configuration row
                        SidebarRow(
                            title: "API Settings",
                            systemImage: "network",
                            isSelected: selectedTab == .apiSettings
                        ) {
                            selectedTab = .apiSettings
                        }
                        
                        // History row
                        SidebarRow(
                            title: "History",
                            systemImage: "clock",
                            isSelected: selectedTab == .history
                        ) {
                            selectedTab = .history
                        }
                        
                        HStack {
                            Text("AI ACTIONS")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        
                        // Custom action rows
                        ForEach(settings.promptActions) { action in
                            SidebarRow(
                                title: action.title.isEmpty ? "Untitled Action" : action.title,
                                systemImage: "sparkles",
                                isSelected: selectedTab == .action(action.id)
                            ) {
                                selectedTab = .action(action.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                
                Spacer()
                
                // Add new prompt action button at the bottom of sidebar
                Button(action: addNewAction) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Action")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(settings.themeAccentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(width: 220)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
            
            Divider()
            
            // Right Detail Area
            VStack {
                switch selectedTab {
                case .apiSettings:
                    ApiSettingsView(settings: settings)
                case .history:
                    HistoryView()
                case .action(let id):
                    ActionEditorView(
                        settings: settings,
                        actionId: id,
                        onDelete: {
                            // 1. Instantly switch tab to global api settings to dismantle the ActionEditorView
                            selectedTab = .apiSettings
                            
                            // 2. Perform the array deletion safely in the background main thread loop
                            DispatchQueue.main.async {
                                if let index = settings.promptActions.firstIndex(where: { $0.id == id }) {
                                    settings.promptActions.remove(at: index)
                                }
                            }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
        }
        .frame(minWidth: 800, idealWidth: 850, maxWidth: .infinity, minHeight: 500, idealHeight: 530, maxHeight: .infinity)
    }
    
    private func addNewAction() {
        let uniqueId = UUID()
        let newAction = PromptAction(
            id: uniqueId,
            title: "New Action",
            systemPrompt: "You are a helpful assistant.",
            template: "Analyze the following:\n\n{{TEXT}}",
            shortcutId: "shortcut_\(uniqueId.uuidString.replacingOccurrences(of: "-", with: "_"))"
        )
        settings.promptActions.append(newAction)
        selectedTab = .action(uniqueId)
    }
}

// MARK: - Sidebar Row Helper
struct SidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        let themeAccentColor = AppSettings.shared.themeAccentColor
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .white : themeAccentColor)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? themeAccentColor : (isHovered ? themeAccentColor.opacity(0.12) : Color.clear))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Global API Settings Editor
struct ApiSettingsView: View {
    @Bindable var settings: AppSettings
    
    enum TestStatus: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }
    
    @State private var testStatuses: [UUID: TestStatus] = [:]
    
    private func colorForName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "emerald": return .green
        case "amber": return .orange
        case "graphite": return .gray
        default: return .purple
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // General App Settings Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("General Settings")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $settings.showPreviewPopover) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show Preview Popover")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Review, edit, or copy the AI response before pasting it into the active app.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .tint(settings.themeAccentColor)
                        
                        Divider()
                        
                        HStack(spacing: 40) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Accent Color")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                
                                HStack(spacing: 12) {
                                    ForEach(["blue", "emerald", "amber", "graphite", "purple"], id: \.self) { colorName in
                                        AccentColorCircle(
                                            colorName: colorName,
                                            settings: settings,
                                            color: colorForName(colorName)
                                        )
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("HUD OSD Theme")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                
                                Picker("", selection: $settings.hudTheme) {
                                    Text("System").tag("system")
                                    Text("Light").tag("light")
                                    Text("Dark").tag("dark")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 200)
                                .labelsHidden()
                            }
                        }
                        
                        Divider()
                        
                        HStack(spacing: 30) {
                            Toggle("Enable Premium Sounds", isOn: $settings.enableSoundEffects)
                                .toggleStyle(.checkbox)
                                .tint(settings.themeAccentColor)
                            
                            Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                                .toggleStyle(.checkbox)
                                .tint(settings.themeAccentColor)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(settings.themeAccentColor.opacity(0.2), lineWidth: 1)
                )
                
                Divider()
                
                HStack {
                    Text("API Configuration Profiles")
                        .font(.title2.bold())
                    Spacer()
                    
                    Button {
                        let newConfig = APIConfig(name: "New Profile", apiBaseURL: "http://localhost:11434/v1", apiKey: "", modelName: "llama3")
                        settings.apiConfigs.append(newConfig)
                    } label: {
                        Label("Add Profile", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(settings.themeAccentColor)
                }
                .padding(.bottom, 10)
                
                VStack(spacing: 16) {
                    ForEach(settings.apiConfigs) { config in
                        if let index = settings.apiConfigs.firstIndex(where: { $0.id == config.id }) {
                            let isActive = settings.activeConfigId == config.id
                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 12) {
                                    Button {
                                        settings.activeConfigId = config.id
                                    } label: {
                                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(isActive ? settings.themeAccentColor : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    TextField("Profile Name", text: $settings.apiConfigs[index].name)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 14, weight: .semibold))
                                    
                                    Spacer()
                                    
                                    // Clone profile button (always available)
                                    Button {
                                        let original = settings.apiConfigs[index]
                                        let clone = APIConfig(
                                            id: UUID(),
                                            name: "\(original.name) Copy",
                                            apiBaseURL: original.apiBaseURL,
                                            apiKey: original.apiKey,
                                            modelName: original.modelName,
                                            fallbackConfigId: original.fallbackConfigId
                                        )
                                        // Copy Keychain item for the cloned profile ID
                                        let keychainKey = "com.smarttextkey.apikey.\(clone.id.uuidString)"
                                        KeychainHelper.shared.save(key: keychainKey, value: original.apiKey)
                                        
                                        settings.apiConfigs.append(clone)
                                        settings.activeConfigId = clone.id
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundStyle(settings.themeAccentColor)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Clone Profile")
                                    .padding(.trailing, 6)
                                    
                                    if settings.apiConfigs.count > 1 {
                                        Button {
                                            // Switch active profile before deletion if deleting the active one
                                            if isActive {
                                                if let alternative = settings.apiConfigs.first(where: { $0.id != config.id }) {
                                                    settings.activeConfigId = alternative.id
                                                }
                                            }
                                            // Deletion is processed safely on main thread loop
                                            DispatchQueue.main.async {
                                                if let deleteIndex = settings.apiConfigs.firstIndex(where: { $0.id == config.id }) {
                                                    settings.apiConfigs.remove(at: deleteIndex)
                                                }
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Delete Profile")
                                    }
                                }
                                
                                if isActive {
                                    Divider()
                                        .padding(.vertical, 4)
                                    
                                    VStack(alignment: .leading, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("API Base URL")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.secondary)
                                            TextField("e.g. http://localhost:11434/v1", text: $settings.apiConfigs[index].apiBaseURL)
                                                .textFieldStyle(.roundedBorder)
                                                .font(.system(size: 12, design: .monospaced))
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("API Key (optional for local API)")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.secondary)
                                            SecureApiKeyField(apiKey: $settings.apiConfigs[index].apiKey)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Model Name")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.secondary)
                                            ModelSearchPicker(
                                                modelName: $settings.apiConfigs[index].modelName,
                                                baseURL: settings.apiConfigs[index].apiBaseURL,
                                                apiKey: settings.apiConfigs[index].apiKey,
                                                themeAccentColor: settings.themeAccentColor
                                            )
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Fallback API Profile (Automated connection failover)")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.secondary)
                                            
                                            Picker("", selection: $settings.apiConfigs[index].fallbackConfigId) {
                                                Text("None").tag(UUID?.none)
                                                ForEach(settings.apiConfigs.filter { $0.id != config.id }) { other in
                                                    Text(other.name).tag(UUID?.some(other.id))
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            .labelsHidden()
                                        }
                                        
                                        // Connection Diagnostics Tool
                                        HStack(spacing: 12) {
                                            Button {
                                                let baseURL = settings.apiConfigs[index].apiBaseURL
                                                let apiKey = settings.apiConfigs[index].apiKey
                                                let configId = config.id
                                                
                                                testStatuses[configId] = .testing
                                                Task {
                                                    do {
                                                        let result = try await AIService.shared.verifyConnection(baseURL: baseURL, apiKey: apiKey)
                                                        testStatuses[configId] = .success(result)
                                                    } catch {
                                                        testStatuses[configId] = .failure(error.localizedDescription)
                                                    }
                                                }
                                            } label: {
                                                HStack(spacing: 6) {
                                                    if testStatuses[config.id] == .testing {
                                                        ProgressView()
                                                            .controlSize(.small)
                                                            .scaleEffect(0.6)
                                                    } else {
                                                        Image(systemName: "bolt.horizontal.fill")
                                                    }
                                                    Text("Test Connection")
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(testStatuses[config.id] == .testing)
                                            
                                            if let status = testStatuses[config.id] {
                                                switch status {
                                                case .idle:
                                                    EmptyView()
                                                case .testing:
                                                    Text("Connecting...")
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(.secondary)
                                                case .success(let msg):
                                                    Label(msg, systemImage: "checkmark.circle.fill")
                                                        .font(.system(size: 11, weight: .medium))
                                                        .foregroundStyle(.green)
                                                case .failure(let err):
                                                    Label(err, systemImage: "exclamationmark.triangle.fill")
                                                        .font(.system(size: 11, weight: .medium))
                                                        .foregroundStyle(.red)
                                                        .help(err)
                                                        .lineLimit(1)
                                                }
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                    .padding(.leading, 28)
                                }
                            }
                            .padding(14)
                            .background(Color(NSColor.controlBackgroundColor).opacity(isActive ? 0.6 : 0.2))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isActive ? settings.themeAccentColor.opacity(0.6) : Color.secondary.opacity(0.1), lineWidth: 1)
                            )
                        }
                    }
                }
                
                Spacer()
            }
            .padding(24)
        }
    }
}

// MARK: - Prompt Action Editor
struct ActionEditorView: View {
    @Bindable var settings: AppSettings
    let actionId: UUID
    let onDelete: () -> Void
    
    var body: some View {
        if let index = settings.promptActions.firstIndex(where: { $0.id == actionId }) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("Edit Action")
                                .font(.title2.bold())
                            Spacer()
                            
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete", systemImage: "trash")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red.opacity(0.15))
                            .foregroundColor(.red)
                        }
                        .padding(.bottom, 10)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Action Title")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField("e.g. Refactor, Translate to Russian", text: $settings.promptActions[index].title)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Configuration Profile")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                            
                            Picker("", selection: $settings.promptActions[index].apiConfigId) {
                                Text("Inherit Global Active Profile (\(settings.activeConfig.name))")
                                    .tag(UUID?.none)
                                
                                ForEach(settings.apiConfigs) { config in
                                    Text(config.name)
                                        .tag(UUID?.some(config.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Global Shortcut")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                KeyboardShortcuts.Recorder(for: KeyboardShortcuts.Name(settings.promptActions[index].shortcutId))
                                    .padding(.vertical, 2)
                                
                                Spacer()
                                
                                Text("Press keys to record.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("System Prompt (AI Role & Instructions)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                            
                            TextEditor(text: $settings.promptActions[index].systemPrompt)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(height: 100)
                                .padding(4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("User Prompt Template")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Must include {{TEXT}}")
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                            }
                            
                            TextEditor(text: $settings.promptActions[index].template)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(height: 120)
                                .padding(4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Response Suffix (Optional)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Appends text literally to the end of any generated AI response")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            TextEditor(text: Binding(
                                get: { settings.promptActions[index].responseSuffix ?? "" },
                                set: { settings.promptActions[index].responseSuffix = $0.isEmpty ? nil : $0 }
                            ))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 80)
                            .padding(4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    .padding(24)
                }
            }
        } else {
            ContentUnavailableView("Action Not Found", systemImage: "questionmark.circle")
        }
    }
}

// MARK: - Visual Effect View Wrapper
public struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    public init(material: NSVisualEffectView.Material = .sidebar, blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material
        self.blendingMode = blendingMode
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Secure API Key Text Field with Visibility Toggle (Eye Icon)
struct SecureApiKeyField: View {
    @Binding var apiKey: String
    @State private var isSecured: Bool = true
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isSecured {
                    SecureField("Enter API Key", text: $apiKey)
                } else {
                    TextField("Enter API Key", text: $apiKey)
                }
            }
            .focused($isFocused)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .padding(.leading, 8)
            .padding(.vertical, 6)
            
            Button {
                isSecured.toggle()
                // Re-focus the field to prevent losing keyboard focus
                isFocused = true
            } label: {
                Image(systemName: isSecured ? "eye" : "eye.slash")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .help(isSecured ? "Show API Key" : "Hide API Key")
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isFocused ? AppSettings.shared.themeAccentColor : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Editable & Searchable Combobox Model Picker
struct ModelSearchPicker: View {
    @Binding var modelName: String
    let baseURL: String
    let apiKey: String
    let themeAccentColor: Color
    
    @State private var isShowingSuggestions = false
    @State private var searchText = ""
    @FocusState private var isFocused: Bool
    
    @State private var dynamicModels: [String] = []
    @State private var isLoadingModels = false
    
    private let suggestedModels = [
        // Ollama / Local Models
        "llama3", "llama3.1", "llama3:70b", "mistral", "phi3", "gemma", "deepseek-coder", "qwen2",
        // OpenAI Models
        "gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo",
        // Anthropic Models
        "claude-3-5-sonnet-latest", "claude-3-opus-latest", "claude-3-haiku-latest",
        // DeepSeek Models
        "deepseek-chat", "deepseek-coder"
    ]
    
    var modelsToUse: [String] {
        dynamicModels.isEmpty ? suggestedModels : dynamicModels
    }
    
    var filteredSuggestions: [String] {
        if searchText.isEmpty {
            return modelsToUse
        } else {
            return modelsToUse.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    private func fetchModels() {
        guard !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.dynamicModels = []
            return
        }
        
        isLoadingModels = true
        Task {
            let fetched = await AIService.shared.fetchAvailableModels(baseURL: baseURL, apiKey: apiKey)
            await MainActor.run {
                self.isLoadingModels = false
                self.dynamicModels = fetched
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                TextField("e.g. llama3, gpt-4o", text: $modelName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced)) // Slightly larger font size
                    .padding(.leading, 10)
                    .padding(.vertical, 8) // Slightly larger padding
                    .focused($isFocused)
                    .onChange(of: modelName) { _, newValue in
                        searchText = newValue
                    }
                    .onChange(of: isFocused) { _, newValue in
                        if newValue {
                            searchText = modelName
                            isShowingSuggestions = true
                            fetchModels()
                        }
                    }
                
                Button {
                    isShowingSuggestions.toggle()
                    if isShowingSuggestions {
                        fetchModels()
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isFocused ? themeAccentColor : Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .popover(isPresented: $isShowingSuggestions, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Select or Type a Model")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if isLoadingModels {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    
                    Divider()
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            if isLoadingModels && dynamicModels.isEmpty {
                                HStack {
                                    Spacer()
                                    Text("Fetching models from server...")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.vertical, 20)
                            } else if filteredSuggestions.isEmpty {
                                Button {
                                    isShowingSuggestions = false
                                } label: {
                                    HStack {
                                        Text("Use Custom: \(searchText)")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(themeAccentColor)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            } else {
                                ForEach(filteredSuggestions, id: \.self) { suggestion in
                                    ModelSuggestionRow(
                                        suggestion: suggestion,
                                        isSelected: modelName == suggestion,
                                        themeAccentColor: themeAccentColor
                                    ) {
                                        modelName = suggestion
                                        isShowingSuggestions = false
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }
                    .frame(maxHeight: 280) // Larger height so they can see many models!
                }
                .frame(width: 320) // Much wider width so everything is beautifully visible!
            }
        }
    }
}

// MARK: - Autocomplete Row Helper Struct
struct ModelSuggestionRow: View {
    let suggestion: String
    let isSelected: Bool
    let themeAccentColor: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(suggestion)
                    .font(.system(size: 12, design: .monospaced)) // Slightly larger suggestion font
                    .foregroundStyle(isSelected ? themeAccentColor : .primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold)) // Slightly larger checkmark
                        .foregroundStyle(themeAccentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6) // Slightly larger row padding
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? themeAccentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Extracted Accent Color Circle Helper
struct AccentColorCircle: View {
    let colorName: String
    @Bindable var settings: AppSettings
    let color: Color
    
    var body: some View {
        let isSelected = settings.accentColor == colorName
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(0.8), lineWidth: isSelected ? 2 : 0)
                    .padding(-3)
            )
            .contentShape(Circle())
            .onTapGesture {
                settings.accentColor = colorName
            }
            .help(colorName.capitalized)
    }
}
