# LocalAI

A native macOS SwiftUI app that provides a voice interface to a locally running [Ollama](https://ollama.com) instance. Everything runs on your machine — no data is sent to the internet.

## How It Works

1. **Hold the button** and speak into your microphone
2. **Release** to send your transcribed speech to Ollama
3. **Listen** as the AI response is spoken back to you

All three stages are fully local:
- **Speech-to-text** — Apple's on-device speech recognition (`requiresOnDeviceRecognition = true`)
- **LLM inference** — Ollama running on `localhost:11434`
- **Text-to-speech** — Apple's `AVSpeechSynthesizer` (on-device)

## Requirements

- macOS 13.0 or later
- Xcode 15+
- [Ollama](https://ollama.com) installed and running locally
- The following Ollama models (personas) must exist:
  - `personal`
  - `developer`
  - `salesforce`
  - `content`

## Setup

### 1. Install Ollama

Download from [ollama.com](https://ollama.com) or install via Homebrew:

```bash
brew install ollama
```

### 2. Create persona models

Each persona is an Ollama model. Create them using Modelfiles or pull base models and create aliases:

```bash
# Example: create a persona from a base model with a custom system prompt
cat > Modelfile <<EOF
FROM llama3.3:70b
SYSTEM "You are a personal assistant. Be helpful and concise."
EOF
ollama create personal -f Modelfile
```

Repeat for `developer`, `salesforce`, and `content` with appropriate system prompts.

### 3. Start Ollama

```bash
ollama serve
```

### 4. Build and run

Open `LocalAI.xcodeproj` in Xcode, then build and run (Cmd+R).

Or build from the command line:

```bash
xcodebuild -project LocalAI.xcodeproj -scheme LocalAI -configuration Debug build
```

## Permissions

On first launch, macOS will ask for:
- **Microphone access** — required for voice input
- **Speech Recognition** — required for on-device transcription (no data is sent to Apple)

Grant both permissions. If you previously denied them, re-enable in **System Settings > Privacy & Security**.

## Architecture

The app is built with two Swift files and four components:

| File | Description |
|------|-------------|
| `LocalAIApp.swift` | `@main` entry point, window configuration |
| `ContentView.swift` | All UI, managers, and data models |

| Component | Responsibility |
|-----------|---------------|
| `SpeechManager` | Microphone input and on-device speech-to-text via `SFSpeechRecognizer` |
| `OllamaService` | HTTP communication with Ollama, conversation history management |
| `TTSManager` | Text-to-speech via `AVSpeechSynthesizer` |
| `ContentView` | SwiftUI interface with hold-to-speak interaction |

### Data flow

```
Mic -> SpeechManager (on-device STT) -> OllamaService (localhost) -> TTSManager (on-device TTS)
```

### Conversation memory

`OllamaService` maintains a full `history` array of all messages in the session. The complete history is sent with each request so Ollama has full conversation context. Tap **Clear** to reset.

## UI Overview

- **Header** — "LOCAL AI" title, persona picker (segmented control), Clear button
- **Message list** — Chat bubbles (blue for user, gray for assistant) with selectable text and a copy-to-clipboard button on each message
- **Transcription preview** — Live transcription shown while recording
- **Status indicator** — Color-coded dot: red (listening), orange (thinking), green (speaking), blue (idle)
- **Hold-to-speak button** — Full-width button at the bottom; hold to record, release to send

## Keyboard Shortcut

**F5** toggles recording — press once to start, press again to stop and send. Designed for Stream Deck integration: create a Hotkey action mapped to F5 on your Stream Deck.

## Dependencies

None. Only Apple frameworks:
- `Speech` (on-device speech recognition)
- `AVFoundation` (audio engine, text-to-speech)
- `SwiftUI`

## License

MIT
