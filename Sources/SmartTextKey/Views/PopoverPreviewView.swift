import SwiftUI
import Observation

// MARK: - Reactive Streaming State for HUDs
@Observable
@MainActor
public final class StreamingState {
    public static let shared = StreamingState()
    
    public var text: String = ""
    public var tokenCount: Int = 0
    public var isStreaming: Bool = false
    
    private init() {}
    
    public func reset() {
        text = ""
        tokenCount = 0
        isStreaming = false
    }
}

// MARK: - Keycap Badge Helper for UI Hints
struct KeycapBadge: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.08))
            .cornerRadius(4)
            .foregroundStyle(.secondary)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
            )
    }
}

// MARK: - Popover Preview View
struct PopoverPreviewView: View {
    @Bindable private var state = StreamingState.shared
    @Bindable private var settings = AppSettings.shared
    
    let promptTitle: String
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onRegenerate: () -> Void
    let onCancel: () -> Void
    
    @State private var copyFeedback = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.linearGradient(colors: [settings.themeAccentColor, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text("AI Result Preview: \(promptTitle)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                
                Spacer()
                
                if state.isStreaming {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)
                        Text("Streaming...")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Ready")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(settings.themeAccentColor.opacity(0.8))
                        .cornerRadius(4)
                }
            }
            
            // Text Preview Box
            ScrollViewReader { proxy in
                ScrollView {
                    Text(state.text.isEmpty ? "Waiting for AI response..." : state.text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(state.text.isEmpty ? .secondary : .primary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("bottom_marker")
                }
                .frame(maxHeight: 280)
                .background(Color(NSColor.textBackgroundColor).opacity(0.4))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                .onChange(of: state.text) { _, _ in
                    // Automatically scroll to bottom during real-time streaming
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom_marker", anchor: .bottom)
                    }
                }
            }
            
            // Actions Row with Keycap Badges and Custom Accent Theme
            HStack(spacing: 10) {
                // Discard Button
                Button(action: onCancel) {
                    HStack(spacing: 6) {
                        Text("Discard")
                        KeycapBadge(text: "⎋ Esc")
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction) // Binds to ESC
                
                Spacer()
                
                // Copy Button
                Button(action: {
                    onCopy()
                    withAnimation {
                        copyFeedback = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation {
                            copyFeedback = false
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: copyFeedback ? "checkmark" : "doc.on.doc")
                        Text(copyFeedback ? "Copied" : "Copy")
                        KeycapBadge(text: "⌘C")
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("c", modifiers: .command) // Binds to Cmd+C
                .disabled(copyFeedback)
                
                // Regenerate Button
                Button(action: onRegenerate) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Regenerate")
                        KeycapBadge(text: "⌘R")
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("r", modifiers: .command) // Binds to Cmd+R
                .disabled(state.isStreaming)
                
                // Paste Button
                Button(action: onPaste) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Paste")
                        KeycapBadge(text: "↩ Enter")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(settings.themeAccentColor)
                .keyboardShortcut(.defaultAction) // Binds to Return/Enter
                .disabled(state.isStreaming || state.text.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 480, height: 380)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    }
}
