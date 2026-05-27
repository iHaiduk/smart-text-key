import SwiftUI
import Observation
import KeyboardShortcuts

struct AppBindingOption: Hashable {
    let name: String
    let bundleId: String
}

struct ActionEditorView: View {
    @Bindable var settings: AppSettings
    let actionId: UUID
    let onDelete: () -> Void

    @State private var cachedRunningApps: [AppBindingOption] = []

    private func updateRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
        
        var list: [AppBindingOption] = apps.compactMap { (app: NSRunningApplication) -> AppBindingOption? in
            guard let name = app.localizedName, let bid = app.bundleIdentifier else { return nil }
            return AppBindingOption(name: name, bundleId: bid)
        }
        
        if let index = settings.promptActions.firstIndex(where: { $0.id == actionId }),
           let currentBid = settings.promptActions[index].bundleId,
           !list.contains(where: { $0.bundleId == currentBid }) {
            list.append(AppBindingOption(name: currentBid, bundleId: currentBid))
        }
        
        cachedRunningApps = list.sorted(by: { $0.name < $1.name })
    }

    var body: some View {
        if let index = settings.promptActions.firstIndex(where: { $0.id == actionId }) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text(settings.localized("edit_action_title"))
                                .font(.title2.bold())
                            Spacer()

                            Button(role: .destructive, action: onDelete) {
                                Label(settings.localized("delete_button"), systemImage: "trash")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red.opacity(0.15))
                            .foregroundColor(.red)
                        }
                        .padding(.bottom, 10)

                        // 1. Action Title
                        VStack(alignment: .leading, spacing: 4) {
                            Text(settings.localized("action_title_label"))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                            TextField(settings.localized("action_title_placeholder"), text: $settings.promptActions[index].title)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                            Text(settings.localized("action_title_desc"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        // 2. Is Snippet Toggle
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(settings.localized("is_snippet_label"), isOn: $settings.promptActions[index].isSnippet)
                                .toggleStyle(.checkbox)
                                .tint(settings.themeAccentColor)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(settings.localized("is_snippet_desc"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        // 3. Application Binding Picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text(settings.localized("app_binding_label"))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)

                            Picker("", selection: $settings.promptActions[index].bundleId) {
                                Text(settings.localized("global_application"))
                                    .tag(String?.none)

                                ForEach(cachedRunningApps, id: \.bundleId) { app in
                                    Text(app.name)
                                        .tag(String?.some(app.bundleId))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            
                            Text(settings.localized("app_binding_desc"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        // 4. API Configuration Profile (only shown for AI actions)
                        if !settings.promptActions[index].isSnippet {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(settings.localized("api_profile_label"))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)

                                Picker("", selection: $settings.promptActions[index].apiConfigId) {
                                    Text(String(format: settings.localized("inherit_global_active_profile"), settings.activeConfig.name))
                                        .tag(UUID?.none)

                                    ForEach(settings.apiConfigs) { config in
                                        Text(config.name)
                                            .tag(UUID?.some(config.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                
                                Text(settings.localized("api_profile_desc"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // 5. Global Shortcut
                        VStack(alignment: .leading, spacing: 4) {
                            Text(settings.localized("global_shortcut_label"))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)

                            HStack {
                                KeyboardShortcuts.Recorder(for: KeyboardShortcuts.Name(settings.promptActions[index].shortcutId))
                                    .padding(.vertical, 2)

                                Spacer()

                                Text(settings.localized("press_keys_to_record"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            
                            Text(settings.localized("global_shortcut_desc"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        // 6. System Prompt (only shown for AI actions)
                        if !settings.promptActions[index].isSnippet {
                            promptEditor(
                                title: settings.localized("system_prompt_label"),
                                text: $settings.promptActions[index].systemPrompt,
                                description: settings.localized("system_prompt_desc"),
                                height: 100
                            )
                        }

                        // 7. Prompt Template / Snippet Content
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(settings.promptActions[index].isSnippet ? settings.localized("snippet_content_label") : settings.localized("user_prompt_template_label"))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(settings.promptActions[index].isSnippet ? settings.localized("supports_clipboard_date_app") : settings.localized("must_include_text_supports_lang"))
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
                            
                            Text(settings.promptActions[index].isSnippet 
                                 ? settings.localized("prompt_template_desc_snippet") 
                                 : settings.localized("prompt_template_desc_ai"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        // 8. Response Suffix (only shown for AI actions)
                        if !settings.promptActions[index].isSnippet {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(settings.localized("response_suffix_label"))
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(settings.localized("appends_text_literally"))
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
                                
                                Text(settings.localized("response_suffix_desc"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(24)
                }
            }
            .onAppear {
                updateRunningApps()
            }
            .onChange(of: actionId, initial: true) { _, _ in
                updateRunningApps()
            }
        } else {
            ContentUnavailableView(settings.localized("action_not_found"), systemImage: "questionmark.circle")
        }
    }

    private func promptEditor(title: String, text: Binding<String>, description: String, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            TextEditor(text: text)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: height)
                .padding(4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            
            Text(description)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
