# 🔮 Smart Text Key

[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue.svg)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/swift-6.0-orange.svg)](https://swift.org)
[![Version](https://img.shields.io/badge/version-1.4.0-purple.svg)]()
[![Build](https://img.shields.io/badge/build-passing-brightgreen.svg)]()
[![License](https://img.shields.io/badge/license-MIT-lightgrey.svg)]()

**Smart Text Key** is a premium, ultra-fast, background-only macOS menu bar utility that brings local and cloud LLM intelligence directly into any text editing area on your system. Press a global hotkey → AI transforms your selected text → result pastes back in-place. Zero friction. Zero context switch.

Designed for developers, writers, and power users who want seamless AI integration without heavy apps, browser tabs, or recurring authorization prompts.

---

## 🗺️ Table of Contents

- [✨ Features](#-features)
- [🆕 What's New in v1.4.0](#-whats-new-in-v140)
- [💻 Tech Stack](#-tech-stack)
- [🚀 Getting Started](#-getting-started)
- [📖 How to Use](#-how-to-use)
- [🌍 Supported Languages](#-supported-languages)
- [🔒 Security & Privacy](#-security--privacy)
- [Troubleshooting](#troubleshooting)
- [📄 License](#-license)

---

## ✨ Features

### ⚡ Core Pipeline

- **In-Place Text Transformation** — Select any text in any macOS app (Xcode, VS Code, Slack, Safari, Terminal), press your hotkey, watch it transform instantly.
- **Real-Time SSE Streaming** — Token-by-token AI streaming inside a glassmorphism popover with live character counting.
- **Multi-Provider AI Routing** — OpenAI, Anthropic, Ollama (local), DeepSeek, or any OpenAI-compatible endpoint — per-action granularity.
- **Automated API Failover** — Attach a fallback profile to any primary API config. If the primary goes offline, the pipeline silently retries on the backup.
- **Escape to Cancel** — Press `⎋ Esc` at any time during streaming to instantly cancel the active generation task.
- **Smart Selection Fallback** — No selection? The pipeline auto-selects the entire document (`⌘A`) as input and replaces it cleanly.

### 🎛️ Actions System

- **Unlimited Custom Actions** — Create any number of AI actions, each with its own system prompt, user template, API profile, and global hotkey.
- **Text Snippets** — Mark any action as a static "Snippet" — it instantly pastes local text (supports `{{CLIPBOARD}}`, `{{DATE}}`, `{{CURRENT_APP}}` placeholders) with no AI request.
- **Per-App Action Binding** — Bind an action to a specific macOS application. The pipeline checks the frontmost app and runs the most specific matching action, falling back to the global variant.
- **Dynamic Template Variables** — Templates support `{{TEXT}}`, `{{CLIPBOARD}}`, `{{DATE}}`, `{{CURRENT_APP}}`, and `{{LANGUAGE}}` (injects the active app language for multilingual workflows).
- **Response Suffix** — Append a static text literal to the end of any AI response (e.g. citations, line separators, signatures).

### 🔍 Interactive HUD Overlays

- **Preview Popover** — A floating glassmorphism overlay shows the AI response streaming in real-time with Paste / Copy / Regenerate / Discard controls.
- **Snippets Quick-Insert HUD** — Global hotkey summons a full-featured search overlay (arrow-key navigation, instant paste on `↩ Enter`, `⎋ Esc` to dismiss).
- **Interactive Fix Mode** — Dedicated hotkey captures your selection and opens a multiline instruction input overlay. Type what you want fixed, press `↩ Enter`, AI applies it. (`⇧ Shift + ↩` or `⌥ Option + ↩` inserts a newline).

### 🎨 Interface & Customization

- **5 Accent Colors** — Blue, Emerald, Amber, Graphite, Purple — dynamically re-colors selection rings, active borders, and all interactive elements.
- **System / Light / Dark Theme** — Independently control the HUD overlay appearance mode separately from macOS system preference.
- **Real-Time Language Switching** — Switch the entire app interface language instantly without restart (14 languages supported).
- **Launch at Login** — Registers via `SMAppService` to auto-start in the menu bar on boot.
- **Sound Feedback** — Plays native macOS sound cues (`Purr` on capture, `Glass` on success, `Basso` on error/fallback).

### 📊 History

- **SQLite-Backed History Log** — Every transformation is logged to a local SQLite database with prompt, original input, AI output, and timestamp.
- **Full-Text Search** — Search history instantly across prompt name, original text, and output.
- **Copy / Delete / Purge** — One-click copy of original or transformed text. Delete individual entries or purge all.

### 🔐 Security

- **Keychain Storage** — API keys are stored in macOS Keychain with owner-only access control — never in plaintext UserDefaults.
- **Zero Cloud Leakage** — Local (Ollama) profiles communicate exclusively with your localhost. No third-party telemetry.
- **Clipboard Preservation** — Original clipboard contents are captured before any operation and cleanly restored after paste.

---

## 🆕 What's New in v1.4.0

### 🌍 Real-Time Multilingual UI (14 Languages)
The entire application interface now supports **14 languages** with instant real-time switching — no restart required:

| Language | Code | Language | Code |
|---|---|---|---|
| 🇺🇸 English | `en` | 🇯🇵 Japanese | `ja` |
| 🇷🇺 Russian | `ru` | 🇰🇷 Korean | `ko` |
| 🇺🇦 Ukrainian | `uk` | 🇻🇳 Vietnamese | `vi` |
| 🇨🇳 Chinese | `zh` | 🇸🇦 Arabic | `ar` |
| 🇪🇸 Spanish | `es` | 🇮🇳 Hindi | `hi` |
| 🇫🇷 French | `fr` | 🇩🇪 German | `de` |
| 🇮🇹 Italian | `it` | 🇵🇹 Portuguese | `pt` |

Switch language in **General Settings → App Language** and every label, button, placeholder, section header, and HUD overlay updates instantly.

### 🔧 Fix Mode — Multiline Instruction Overlay
A dedicated new global hotkey triggers the **Interactive Fix Mode**:
1. Press the Fix Mode hotkey
2. The app captures your current text selection
3. A floating HUD overlay appears with a multiline `TextEditor` for your instruction
4. Type your instruction (e.g. *"translate to English, make it concise"*)
5. Press `↩ Enter` to run — `⇧ Shift + ↩` inserts a newline
6. AI applies your instruction and pastes the result back in-place

### 📌 Snippets Quick-Insert HUD
A brand-new dedicated hotkey summons a full-featured **Snippets Search overlay**:
- Arrow-key navigation through all your configured text snippets
- Instant full-text search
- `↩ Enter` to paste the selected snippet
- `⎋ Esc` to dismiss without action

### 🏗️ Architecture Hardening
- **Provider Isolation** — `OpenAIProvider`, `AnthropicProvider`, `OllamaProvider` are now fully separated into individual provider files with injected `URLSession` (testable, mockable).
- **`TransformationPipeline`** — All capture → process → paste logic is centralized in a dedicated pipeline class with full failover and cancellation support.
- **`AIProviderClientFactory`** — Clean factory pattern replaces the monolithic `AIService` switch block.
- **`nonisolated(unsafe)` eliminated** — `URLSession` is injected via `init`, not stored as an unsafe nonisolated property.
- **Redundant saves eliminated** — `promptActions.didSet` is the single source of truth for persistence + shortcut re-registration. No more double-save from observers.
- **`runningApps` cached** — Application binding picker no longer recomputes the running app list on every SwiftUI render pass.
- **Localization migrated to `.strings` files** — Replaced a 578-line in-memory dictionary with standard Apple `*.lproj/Localizable.strings` resource files loaded via `Bundle.module`. Adding a new language now requires only a new `.lproj` folder.

### 🧪 Expanded Test Suite
17 unit and integration tests now cover:
- SQLite history persistence (`:memory:` isolation)
- Keychain round-trip (save / read / delete)
- OpenAI streaming chunk assembly and response parsing
- Ollama base URL normalization and completion
- Anthropic SSE delta decoding
- `AIService` thinking-block stripping (`<think>`, `<thought>`)
- Per-app action shortcut resolution
- Pipeline fallback, snippet expansion, and empty-response guard

---

## 💻 Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 6.0 (strict concurrency, `Sendable`, `@MainActor`) |
| UI | SwiftUI + AppKit (glassmorphism overlays, `NSVisualEffectView`) |
| Concurrency | Swift structured concurrency (`async/await`, `Task`, `AsyncBytes`) |
| Database | Native SQLite3 (no ORM) |
| Keychain | Security framework (`SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete`) |
| Hotkeys | [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) |
| Localization | Standard Apple `.strings` files via `Bundle.module` |
| Packaging | Swift Package Manager (SPM) |
| CI/CD | GitHub Actions → DMG artifact on every push |

---

## 🚀 Getting Started

### Prerequisites

- macOS 14.0 (Sonoma) or newer
- Xcode 15.0+ **or** Swift Toolchain 6.0+

### 📥 Quick Install (DMG)

Every push to `main` triggers an automated GitHub Actions build:

1. Go to the **Releases** tab of this repository.
2. Download `SmartTextKey.dmg`.
3. Open the DMG, drag **Smart Text Key** into **Applications**, and launch.

> [!IMPORTANT]
> **macOS Gatekeeper Notice:**
> Since the app is not signed/notarized with an Apple Developer certificate, macOS may block the first launch.
>
> **To allow it:**
> 1. Open **System Settings → Privacy & Security**
> 2. Scroll to the *Security* section and click **Open Anyway**
>
> Or via Terminal:
> ```bash
> xattr -dr com.apple.quarantine /Applications/SmartTextKey.app
> ```

### 🔨 Build from Source

```bash
git clone https://github.com/iHaiduk/smart-text-key.git
cd smart-text-key
swift build -c release
```

The compiled binary: `.build/release/SmartTextKey`

To produce a packaged DMG locally:

```bash
./scripts/package_dmg.sh
```

### 🧪 Run Tests

```bash
swift test
```

17 tests covering history, keychain, AI providers, pipeline, and snippet logic.

---

## 📖 How to Use

### 1. First Launch

The app registers as a **background accessory** (no Dock icon) and opens the Settings panel automatically. A `🔮` icon appears in your menu bar.

### 2. Configure API

Open **Settings → API Settings**:

- Click **Add Profile** to create an API endpoint
- Enter your **Base URL** (e.g. `http://localhost:11434/v1` for Ollama, or `https://api.openai.com/v1`)
- Enter your **API Key** (stored securely in macOS Keychain)
- Focus the **Model Name** field to auto-fetch available models from your server
- Optionally attach a **Fallback Profile** for automatic failover

### 3. Create Actions

Open **Settings → AI Actions** and click **Add Action**:

| Field | Description |
|---|---|
| **Title** | Label shown in HUDs and the sidebar |
| **Is Text Snippet** | When on: pastes static text instantly, no AI call |
| **App Binding** | Optional: restrict action to a specific running app |
| **API Profile** | Choose a specific profile or inherit the global active one |
| **Global Shortcut** | Record a system-wide hotkey |
| **System Prompt** | AI persona and rules |
| **User Prompt Template** | Must include `{{TEXT}}`; supports `{{CLIPBOARD}}`, `{{DATE}}`, `{{CURRENT_APP}}`, `{{LANGUAGE}}` |
| **Response Suffix** | Static text appended to every AI response |

### 4. Use Your Hotkeys

| Action | How |
|---|---|
| **AI Transform** | Select text → press your action hotkey → AI transforms in-place |
| **Snippets Search** | Press Snippets hotkey → arrow-key navigate → `↩` to paste |
| **Fix Mode** | Press Fix Mode hotkey → type instruction → `↩` to apply |
| **Cancel streaming** | Press `⎋ Esc` at any time |

### 5. Preview Popover (Optional)

Enable **Show Preview Popover** to review the AI output before pasting:

| Key | Action |
|---|---|
| `↩ Enter` | Paste result at cursor |
| `⌘C` | Copy to clipboard |
| `⌘R` | Regenerate (restart AI call) |
| `⎋ Esc` | Discard and restore original clipboard |

---

## 🌍 Supported Languages

Switch the UI language in **General Settings → App Language**. Changes apply instantly across all views, overlays, and HUDs:

- 🇺🇸 English · 🇷🇺 Russian · 🇺🇦 Ukrainian · 🇨🇳 Chinese · 🇻🇳 Vietnamese
- 🇪🇸 Spanish · 🇫🇷 French · 🇩🇪 German · 🇮🇹 Italian · 🇵🇹 Portuguese
- 🇯🇵 Japanese · 🇰🇷 Korean · 🇸🇦 Arabic · 🇮🇳 Hindi

The app also reads your macOS system locale by default (`System Language` option), so if your system is in Russian, the UI starts in Russian automatically.

---

## 🔒 Security & Privacy

- **API keys** are stored in macOS Keychain with `kSecAttrAccessible` owner-only policy — never in `UserDefaults` or plain files.
- **Local-only** Ollama profiles talk exclusively to your `localhost` — no data leaves your machine.
- **Clipboard preservation** — the original clipboard is snapshotted before any operation and restored immediately after the paste, leaving no residual data.
- **No telemetry** — the app makes zero analytics or tracking requests. It only calls the API endpoints you explicitly configure.

---

## Troubleshooting

### "SmartTextKey is damaged and can't be opened"

The build is not signed/notarized. Clear Gatekeeper quarantine:

```bash
xattr -dr com.apple.quarantine /Applications/SmartTextKey.app
```

### Hotkey doesn't trigger

Make sure **Accessibility permissions** are granted:  
**System Settings → Privacy & Security → Accessibility** → enable Smart Text Key.

### Text doesn't get replaced

- Ensure the target app supports standard macOS `NSPasteboard` paste operations.
- Some sandboxed apps or password fields block programmatic paste — this is a macOS security limitation.

### No models appear in the model picker

- For Ollama: confirm the server is running (`ollama serve`) and accessible at the configured base URL.
- For OpenAI/cloud: ensure your API key is valid and the base URL matches the provider's endpoint.

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.
