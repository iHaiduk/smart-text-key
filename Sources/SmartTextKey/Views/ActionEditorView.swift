import SwiftUI
import Observation
import KeyboardShortcuts

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

                        promptEditor(
                            title: "System Prompt (AI Role & Instructions)",
                            text: $settings.promptActions[index].systemPrompt,
                            height: 100
                        )

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

    private func promptEditor(title: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
        }
    }
}
