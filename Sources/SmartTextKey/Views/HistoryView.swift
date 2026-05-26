import SwiftUI

struct HistoryView: View {
    @State private var historyItems: [HistoryItem] = []
    @State private var searchText: String = ""
    @State private var expandedItems: Set<Int64> = []
    @State private var showClearConfirmation = false
    
    // Formatter for timestamps
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
    
    var filteredItems: [HistoryItem] {
        if searchText.isEmpty {
            return historyItems
        }
        return historyItems.filter { item in
            item.promptTitle.localizedCaseInsensitiveContains(searchText) ||
            item.inputText.localizedCaseInsensitiveContains(searchText) ||
            item.outputText.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header Title & Global Action
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transformation History")
                        .font(.title2.bold())
                    Text("Review, copy, or delete past text transformations")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if !historyItems.isEmpty {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Clear All", systemImage: "trash.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red.opacity(0.8))
                    .confirmationDialog(
                        "Are you sure you want to clear all transformation history?",
                        isPresented: $showClearConfirmation
                    ) {
                        Button("Clear All", role: .destructive) {
                            HistoryManager.shared.clearAll()
                            loadHistory()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently delete all records of past text transformations. This action cannot be undone.")
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            // Search Bar & Filter
            if !historyItems.isEmpty || !searchText.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search by prompt, input, or output...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 24)
            }
            
            // History Listing
            if filteredItems.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "clock" : "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .opacity(0.6)
                        .padding(.bottom, 8)
                    
                    Text(searchText.isEmpty ? "No transformations yet" : "No matches found")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(searchText.isEmpty ? "Transform text using your dynamic hotkeys to see history here." : "Try adjusting your search criteria.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredItems) { item in
                            HistoryCard(
                                item: item,
                                isExpanded: expandedItems.contains(item.id),
                                onToggleExpand: {
                                    if expandedItems.contains(item.id) {
                                        expandedItems.remove(item.id)
                                    } else {
                                        expandedItems.insert(item.id)
                                    }
                                },
                                onCopy: {
                                    copyToClipboard(item.outputText)
                                },
                                onDelete: {
                                    HistoryManager.shared.delete(id: item.id)
                                    loadHistory()
                                },
                                dateFormatter: dateFormatter
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .onAppear(perform: loadHistory)
    }
    
    private func loadHistory() {
        historyItems = HistoryManager.shared.fetchAll()
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Individual History Card Component
struct HistoryCard: View {
    let item: HistoryItem
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let dateFormatter: DateFormatter
    
    @State private var isHovered = false
    @State private var copyFeedback = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card Header
            HStack(spacing: 12) {
                // Expanded indicator arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                
                // Prompt Title and Date
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.promptTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Text(dateFormatter.string(from: item.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Actions (Copy / Delete)
                HStack(spacing: 6) {
                    Button(action: {
                        onCopy()
                        withAnimation {
                            copyFeedback = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                copyFeedback = false
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: copyFeedback ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                            if copyFeedback {
                                Text("Copied")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(copyFeedback ? Color.green.opacity(0.15) : Color.primary.opacity(0.05))
                        .foregroundStyle(copyFeedback ? .green : .secondary)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Copy transformed output text")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.8))
                            .padding(4)
                            .background(Color.red.opacity(0.05))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Delete transformation record")
                }
                .opacity(isHovered || isExpanded ? 1 : 0.6)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onToggleExpand()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            // Expanded content showing inputs and outputs
            if isExpanded {
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    // Original Text
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Original Text")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        
                        Text(item.inputText)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(6)
                            .lineLimit(10)
                            .textSelection(.enabled)
                    }
                    
                    // Transformed Text
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Transformed Output")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        
                        Text(item.outputText)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentColor.opacity(0.04))
                            .cornerRadius(6)
                            .lineLimit(20)
                            .textSelection(.enabled)
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.01))
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(isExpanded ? 0.6 : 0.3))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isExpanded ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
