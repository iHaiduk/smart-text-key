import SwiftUI
import Observation

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
                generalSettingsSection

                Divider()

                HStack {
                    Text("API Configuration Profiles")
                        .font(.title2.bold())
                    Spacer()

                    Button {
                        let newConfig = APIConfig(
                            name: "New Profile",
                            apiBaseURL: APIProvider.ollama.defaultBaseURL,
                            apiKey: "",
                            modelName: APIProvider.ollama.defaultModelName,
                            providerId: APIProvider.ollama.id
                        )
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
                            apiProfileCard(config: config, index: index)
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
        }
    }

    private var generalSettingsSection: some View {
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
    }

    private func apiProfileCard(config: APIConfig, index: Int) -> some View {
        let isActive = settings.activeConfigId == config.id

        return VStack(alignment: .leading, spacing: 12) {
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

                Button {
                    cloneProfile(at: index)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(settings.themeAccentColor)
                }
                .buttonStyle(.plain)
                .help("Clone Profile")
                .padding(.trailing, 6)

                if settings.apiConfigs.count > 1 {
                    Button {
                        deleteProfile(config: config, isActive: isActive)
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
                    providerPicker(index: index)
                    baseURLField(index: index)
                    apiKeyField(index: index)
                    modelField(index: index)
                    fallbackPicker(config: config, index: index)
                    diagnosticsRow(config: config, index: index)
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

    private func providerPicker(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("API Provider")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)

            Picker("", selection: $settings.apiConfigs[index].providerId) {
                ForEach(APIProvider.all) { provider in
                    Text(provider.title).tag(provider.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: settings.apiConfigs[index].providerId) { oldValue, newValue in
                let oldProvider = APIProvider.provider(for: oldValue)
                let newProvider = APIProvider.provider(for: newValue)
                let baseURL = settings.apiConfigs[index].apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                let modelName = settings.apiConfigs[index].modelName.trimmingCharacters(in: .whitespacesAndNewlines)

                if baseURL.isEmpty || baseURL == oldProvider.defaultBaseURL {
                    settings.apiConfigs[index].apiBaseURL = newProvider.defaultBaseURL
                }

                if modelName.isEmpty || modelName == oldProvider.defaultModelName {
                    settings.apiConfigs[index].modelName = newProvider.defaultModelName
                }
            }
        }
    }

    private func baseURLField(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("API Base URL")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            TextField("e.g. http://localhost:11434/v1", text: $settings.apiConfigs[index].apiBaseURL)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
        }
    }

    private func apiKeyField(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("API Key (optional for local API)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            SecureApiKeyField(apiKey: $settings.apiConfigs[index].apiKey)
        }
    }

    private func modelField(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Model Name")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            ModelSearchPicker(
                modelName: $settings.apiConfigs[index].modelName,
                baseURL: settings.apiConfigs[index].apiBaseURL,
                apiKey: settings.apiConfigs[index].apiKey,
                providerId: settings.apiConfigs[index].providerId,
                themeAccentColor: settings.themeAccentColor
            )
            .id("\(settings.apiConfigs[index].id)-\(settings.apiConfigs[index].providerId)")
        }
    }

    private func fallbackPicker(config: APIConfig, index: Int) -> some View {
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
    }

    private func diagnosticsRow(config: APIConfig, index: Int) -> some View {
        HStack(spacing: 12) {
            Button {
                let baseURL = settings.apiConfigs[index].apiBaseURL
                let apiKey = settings.apiConfigs[index].apiKey
                let providerId = settings.apiConfigs[index].providerId
                let configId = config.id

                testStatuses[configId] = .testing
                Task {
                    do {
                        let result = try await AIService.shared.verifyConnection(
                            baseURL: baseURL,
                            apiKey: apiKey,
                            providerId: providerId
                        )
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
    }

    private func cloneProfile(at index: Int) {
        let original = settings.apiConfigs[index]
        let clone = APIConfig(
            id: UUID(),
            name: "\(original.name) Copy",
            apiBaseURL: original.apiBaseURL,
            apiKey: original.apiKey,
            modelName: original.modelName,
            providerId: original.providerId,
            fallbackConfigId: original.fallbackConfigId
        )
        let keychainKey = "com.smarttextkey.apikey.\(clone.id.uuidString)"
        KeychainHelper.shared.save(key: keychainKey, value: original.apiKey)

        settings.apiConfigs.append(clone)
        settings.activeConfigId = clone.id
    }

    private func deleteProfile(config: APIConfig, isActive: Bool) {
        if isActive, let alternative = settings.apiConfigs.first(where: { $0.id != config.id }) {
            settings.activeConfigId = alternative.id
        }

        DispatchQueue.main.async {
            if let deleteIndex = settings.apiConfigs.firstIndex(where: { $0.id == config.id }) {
                settings.apiConfigs.remove(at: deleteIndex)
            }
        }
    }
}
