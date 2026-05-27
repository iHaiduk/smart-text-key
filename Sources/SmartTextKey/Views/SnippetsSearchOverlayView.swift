import SwiftUI

struct SnippetsSearchOverlayView: View {
    let snippets: [PromptAction]
    let onSelect: (PromptAction) -> Void
    let onCancel: () -> Void
    
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool
    
    var filteredSnippets: [PromptAction] {
        if searchText.isEmpty {
            return snippets
        }
        return snippets.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Input Header
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppSettings.shared.themeAccentColor)
                
                TextField(AppSettings.shared.localized("search_snippets_placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isSearchFocused)
                    .onChange(of: searchText) { _, _ in
                        selectedIndex = 0
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.primary.opacity(0.02))
            
            Divider()
            
            // Interactive Results List
            if filteredSnippets.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text(AppSettings.shared.localized("no_snippets_found"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(Array(filteredSnippets.enumerated()), id: \.element.id) { index, snippet in
                                let isSelected = index == selectedIndex
                                
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.text.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(isSelected ? .white : AppSettings.shared.themeAccentColor)
                                    
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(snippet.title)
                                            .font(.system(size: 13, weight: .bold))
                                        
                                        if !snippet.template.isEmpty {
                                            Text(snippet.template.replacingOccurrences(of: "\n", with: " "))
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if isSelected {
                                        Text("↩ " + AppSettings.shared.localized("paste_label"))
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.9))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.black.opacity(0.2))
                                            .cornerRadius(4)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isSelected ? AppSettings.shared.themeAccentColor : Color.clear)
                                )
                                .foregroundColor(isSelected ? .white : .primary)
                                .contentShape(Rectangle())
                                .id(index)
                                .onTapGesture {
                                    onSelect(snippet)
                                }
                            }
                        }
                        .padding(12)
                    }
                    .frame(maxHeight: .infinity)
                    .onChange(of: selectedIndex) { _, newIndex in
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
            
            Divider()
            
            // Command Bar Footer
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.and.down")
                    Text(AppSettings.shared.localized("navigate_label"))
                }
                Text("•")
                HStack(spacing: 4) {
                    Text("↩")
                        .font(.system(size: 10, weight: .bold))
                    Text(AppSettings.shared.localized("paste_label"))
                }
                Text("•")
                HStack(spacing: 4) {
                    Text("⎋")
                        .font(.system(size: 10, weight: .bold))
                    Text(AppSettings.shared.localized("cancel_button"))
                }
                
                Spacer()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.01))
        }
        .frame(width: 450, height: 350)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .onAppear {
            isSearchFocused = true
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < filteredSnippets.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            if selectedIndex >= 0 && selectedIndex < filteredSnippets.count {
                onSelect(filteredSnippets[selectedIndex])
            }
            return .handled
        }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
    }
}
