<p align="center">
  <img src="AppIcon.png" width="128" height="128" alt="HackerNewsAI App Icon">
</p>

<h1 align="center">HackerNewsAI</h1>

<p align="center">
  <strong>AI-powered Hacker News reader for iOS and macOS</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-iOS%2026%2B%20%7C%20macOS%2026%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-6.2-orange" alt="Swift">
  <img src="https://img.shields.io/badge/Xcode-27-blueviolet" alt="Xcode">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
</p>

---

## Features

- **AI Catch-Up Summaries** — Get a personalized summary of what you missed since your last visit, streamed in as it's generated
- **Apple Intelligence (on-device)** — Direct Foundation Models integration with availability checks, context-budget-aware prompts, and deterministic sampling
- **Multiple LLM Backends** — Choose between on-device Apple Intelligence, local MLX models, or Claude API
- **Native SwiftUI** — Built entirely with SwiftUI for iOS and macOS
- **Threaded Comments** — Browse comment threads with collapsible replies
- **Privacy-First** — On-device options mean your reading habits stay private

## LLM Providers

| Provider | Description | Requirements |
|----------|-------------|--------------|
| **On-Device (Apple)** | Apple Intelligence via Foundation Models (direct adapter). Availability-gated; streams responses; sizes prompts to the model's context window. | iOS 26+ / macOS 26+ with Apple Intelligence enabled. OS 27 recommended. |
| **MLX (Local)** | Runs Qwen3 or Llama models locally | Apple Silicon, ~400MB-2.5GB download |
| **Claude (Anthropic)** | Cloud API with best quality | API key required |

## Requirements

- iOS 26.0+ / macOS 26.0+ (on-device provider requires Apple Intelligence; OS 27 recommended for streaming and context-budget features)
- Xcode 27.0+ (Foundation Models / Swift 6.2 toolchain)
- Swift 6.2+

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/n0an/HackerNewsAI.git
   ```

2. Open `HackerNewsAI.xcodeproj` in Xcode 27

3. Build and run on your device or simulator

> **Build from the command line:** if Xcode 27 isn't your selected toolchain, point `DEVELOPER_DIR` at it:
> ```bash
> DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
>   xcodebuild -project HackerNewsAI.xcodeproj -scheme HackerNewsAI \
>     -destination 'platform=macOS,arch=arm64' build
> ```

## Architecture

The app follows MVVM architecture with feature-based organization:

- **Core** — Models, Services, and Extensions
- **Features** — Feed, Comments, Summary, Settings
- **Modules/LLM** — Swift Package abstracting LLM providers
  - `FoundationModelRuntime` — the single direct bridge to `FoundationModels` (availability probing, `GenerationOptions`, streaming, context budget). All Foundation Models types are fully-qualified to avoid colliding with the vendored `AnyLanguageModel` package, which redeclares the same names. AnyLanguageModel is used only for the Anthropic backend.

## Related Projects

- [HackerNewsAI CLI](https://github.com/n0an/hackernewsai-cli) — Terminal UI version with AI digest, built with Go and Bubble Tea
- [HackerNewsAI Telegram Bot](https://t.me/HackerNewsAI_bot) — Daily AI-curated digests delivered to Telegram

## License

MIT License
