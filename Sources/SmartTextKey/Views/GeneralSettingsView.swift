import SwiftUI
import Observation
import KeyboardShortcuts

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings

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
            VStack(alignment: .leading, spacing: 24) {
                Text(settings.localized("general_settings_title"))
                    .font(.title2.bold())
                    .padding(.bottom, 4)

                // 1. Behavior & Interaction Section
                VStack(alignment: .leading, spacing: 16) {
                    Text(settings.localized("behavior_section"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    Toggle(isOn: $settings.showPreviewPopover) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(settings.localized("show_preview_popover"))
                                .font(.system(size: 13, weight: .semibold))
                            Text(settings.localized("show_preview_popover_desc"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .tint(settings.themeAccentColor)

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text(settings.localized("target_language"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        
                        Text(settings.localized("target_language_desc"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)

                        Picker("", selection: $settings.targetLanguage) {
                            Text(settings.localized("system_language_default")).tag("system")
                            Text("English").tag("en")
                            Text("Spanish (Español)").tag("es")
                            Text("French (Français)").tag("fr")
                            Text("German (Deutsch)").tag("de")
                            Text("Italian (Italiano)").tag("it")
                            Text("Portuguese (Português)").tag("pt")
                            Text("Russian (Русский)").tag("ru")
                            Text("Ukrainian (Українська)").tag("uk")
                            Text("Chinese (中文)").tag("zh")
                            Text("Japanese (日本語)").tag("ja")
                            Text("Korean (한국어)").tag("ko")
                            Text("Vietnamese (Tiếng Việt)").tag("vi")
                            Text("Arabic (العربية)").tag("ar")
                            Text("Hindi (हिन्दी)").tag("hi")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 240)
                        .labelsHidden()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
                .cornerRadius(8)

                // 2. Interface & Styling Section
                VStack(alignment: .leading, spacing: 16) {
                    Text(settings.localized("interface_section"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(settings.localized("accent_color"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        
                        Text(settings.localized("accent_color_desc"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 2)

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

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text(settings.localized("hud_theme"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        
                        Text(settings.localized("hud_theme_desc"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)

                        Picker("", selection: $settings.hudTheme) {
                            Text(settings.localized("theme_system")).tag("system")
                            Text(settings.localized("theme_light")).tag("light")
                            Text(settings.localized("theme_dark")).tag("dark")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                        .labelsHidden()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
                .cornerRadius(8)

                // 3. System Preferences
                VStack(alignment: .leading, spacing: 16) {
                    Text(settings.localized("system_preferences_section"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 40) {
                        Toggle(isOn: $settings.enableSoundEffects) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(settings.localized("sound_effects"))
                                    .font(.system(size: 12, weight: .semibold))
                                Text(settings.localized("sound_effects_desc"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .tint(settings.themeAccentColor)

                        Toggle(isOn: $settings.launchAtLogin) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(settings.localized("launch_at_login"))
                                    .font(.system(size: 12, weight: .semibold))
                                Text(settings.localized("launch_at_login_desc"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .tint(settings.themeAccentColor)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
                .cornerRadius(8)

                // 4. System Hotkeys Section
                VStack(alignment: .leading, spacing: 16) {
                    Text(settings.localized("hotkeys_section"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 40) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(settings.localized("snippets_search_hotkey"))
                                .font(.system(size: 12, weight: .semibold))
                            Text(settings.localized("snippets_search_hotkey_desc"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 240, alignment: .leading)
                            KeyboardShortcuts.Recorder(for: .snippetsSearch)
                                .padding(.top, 2)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(settings.localized("fix_mode_hotkey"))
                                .font(.system(size: 12, weight: .semibold))
                            Text(settings.localized("fix_mode_hotkey_desc"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: 240, alignment: .leading)
                            KeyboardShortcuts.Recorder(for: .fixMode)
                                .padding(.top, 2)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
                .cornerRadius(8)

                // Diagnostic warnings
                if let loginError = settings.launchAtLoginError {
                    Label(loginError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }

                if let dbError = settings.databaseDiagnosticError {
                    Label(dbError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }
            }
            .padding(24)
        }
    }
}
