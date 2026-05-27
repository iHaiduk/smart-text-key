import SwiftUI

struct FixModeInputOverlayView: View {
    let capturedText: String
    let onConfirm: (String) -> Void
    let onCancel: () -> Void
    
    @State private var instruction = ""
    @FocusState private var isInstructionFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Bar
            HStack(spacing: 8) {
                Image(systemName: "pencil.and.outline")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.linearGradient(colors: [AppSettings.shared.themeAccentColor, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text(AppSettings.shared.localized("fix_mode_title"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                
                Spacer()
                
                Text(String(format: AppSettings.shared.localized("captured_chars"), capturedText.count))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
            
            // Captured Context Selection Preview
            VStack(alignment: .leading, spacing: 5) {
                Text(AppSettings.shared.localized("fix_mode_preview"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                
                ScrollView {
                    Text(capturedText.isEmpty ? "No selection captured." : capturedText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 75)
                .background(Color(NSColor.textBackgroundColor).opacity(0.3))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
            }
            
            // Instruction Input
            VStack(alignment: .leading, spacing: 6) {
                Text(AppSettings.shared.localized("fix_mode_instruction"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                
                ZStack(alignment: .topLeading) {
                    if instruction.isEmpty {
                        Text(AppSettings.shared.localized("fix_mode_placeholder"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }
                    
                    TextEditor(text: $instruction)
                        .font(.system(size: 12))
                        .focused($isInstructionFocused)
                        .padding(4)
                        .scrollContentBackground(.hidden)
                        .onKeyPress { keyPress in
                            if keyPress.key == .return {
                                // Allow newline if Shift or Option is held
                                if keyPress.modifiers.contains(.shift) || keyPress.modifiers.contains(.option) {
                                    return .ignored
                                }
                                // Otherwise submit
                                if !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    onConfirm(instruction)
                                    return .handled
                                }
                                return .handled
                            }
                            return .ignored
                        }
                }
                .frame(height: 70)
                .background(Color(NSColor.textBackgroundColor).opacity(0.15))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isInstructionFocused ? AppSettings.shared.themeAccentColor : Color.secondary.opacity(0.15), lineWidth: isInstructionFocused ? 1.5 : 1)
                )
                .shadow(color: isInstructionFocused ? AppSettings.shared.themeAccentColor.opacity(0.2) : Color.clear, radius: 4, x: 0, y: 0)
                .animation(.easeOut(duration: 0.15), value: isInstructionFocused)
            }
            
            // Action Button bar
            HStack {
                Button(action: onCancel) {
                    HStack(spacing: 4) {
                        Text(AppSettings.shared.localized("cancel_button"))
                        KeycapBadge(text: "⎋ Esc")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: {
                    onConfirm(instruction)
                }) {
                    HStack(spacing: 6) {
                        Text(AppSettings.shared.localized("apply_fix_button"))
                        Image(systemName: "sparkles")
                        KeycapBadge(text: "↩ Enter")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppSettings.shared.themeAccentColor)
                .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 450, height: 260)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .onAppear {
            isInstructionFocused = true
        }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
    }
}
