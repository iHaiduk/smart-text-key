import SwiftUI
import Observation

public struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var selectedTab: Selection = .generalSettings

    enum Selection: Hashable {
        case generalSettings
        case apiSettings
        case history
        case action(UUID)
    }

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "character.bubble")
                        .font(.system(size: 24))
                        .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Text Key")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? AppVersion.current)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(settings.localized("global_section"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        SidebarRow(
                            title: settings.localized("general_settings_title"),
                            systemImage: "gearshape",
                            isSelected: selectedTab == .generalSettings
                        ) {
                            selectedTab = .generalSettings
                        }

                        SidebarRow(
                            title: settings.localized("api_settings_title"),
                            systemImage: "network",
                            isSelected: selectedTab == .apiSettings
                        ) {
                            selectedTab = .apiSettings
                        }

                        SidebarRow(
                            title: settings.localized("history_title"),
                            systemImage: "clock",
                            isSelected: selectedTab == .history
                        ) {
                            selectedTab = .history
                        }

                        HStack {
                            Text(settings.localized("ai_actions_section"))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                        ForEach(settings.promptActions) { action in
                            SidebarRow(
                                title: action.title.isEmpty ? settings.localized("untitled_action") : action.title,
                                systemImage: action.isSnippet ? "doc.text.fill" : "sparkles",
                                isSelected: selectedTab == .action(action.id),
                                badgeText: action.isSnippet ? "Snippet" : nil
                            ) {
                                selectedTab = .action(action.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }

                Spacer()

                Button(action: addNewAction) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(settings.localized("add_action_button"))
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

            VStack {
                switch selectedTab {
                case .generalSettings:
                    GeneralSettingsView(settings: settings)
                case .apiSettings:
                    ApiSettingsView(settings: settings)
                case .history:
                    HistoryView()
                case .action(let id):
                    ActionEditorView(
                        settings: settings,
                        actionId: id,
                        onDelete: {
                            selectedTab = .apiSettings

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
            title: settings.localized("new_action_title"),
            systemPrompt: "You are a helpful assistant.",
            template: "Analyze the following:\n\n{{TEXT}}",
            shortcutId: "shortcut_\(uniqueId.uuidString.replacingOccurrences(of: "-", with: "_"))"
        )
        settings.promptActions.append(newAction)
        selectedTab = .action(uniqueId)
    }
}

struct SidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    var badgeText: String? = nil
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

                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? themeAccentColor : .white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white : themeAccentColor.opacity(0.85))
                        .cornerRadius(4)
                }
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
