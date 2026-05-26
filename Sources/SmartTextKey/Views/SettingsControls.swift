import AppKit
import SwiftUI
import Observation

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

struct ModelSearchPicker: View {
    @Binding var modelName: String
    let baseURL: String
    let apiKey: String
    let providerId: String
    let themeAccentColor: Color

    @State private var isShowingSuggestions = false
    @State private var searchText = ""
    @FocusState private var isFocused: Bool

    @State private var dynamicModels: [String] = []
    @State private var isLoadingModels = false

    private var suggestedModels: [String] {
        switch APIProvider.normalizedId(providerId) {
        case APIProvider.ollama.id:
            return ["llama3", "llama3.1", "llama3:70b", "mistral", "phi3", "gemma", "deepseek-coder", "qwen2"]
        case APIProvider.anthropic.id:
            return ["claude-3-5-sonnet-latest", "claude-3-5-haiku-latest", "claude-3-opus-latest"]
        case APIProvider.deepSeek.id:
            return ["deepseek-chat", "deepseek-coder"]
        default:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]
        }
    }

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
            let fetched = await AIService.shared.fetchAvailableModels(
                baseURL: baseURL,
                apiKey: apiKey,
                providerId: providerId
            )
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
                    .font(.system(size: 13, design: .monospaced))
                    .padding(.leading, 10)
                    .padding(.vertical, 8)
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
                    .frame(maxHeight: 280)
                }
                .frame(width: 320)
            }
        }
    }
}

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
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(isSelected ? themeAccentColor : .primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(themeAccentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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
