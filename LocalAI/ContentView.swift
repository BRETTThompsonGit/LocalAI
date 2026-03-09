import SwiftUI
import Speech
import AVFoundation

// MARK: - Data Models

struct Message: Identifiable {
    let id = UUID()
    let role: String
    let content: String
}

struct OllamaMessage: Codable {
    let role: String
    let content: String
}

struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
}

struct OllamaChatResponse: Codable {
    let message: OllamaMessage
}

// MARK: - SpeechManager

class SpeechManager: ObservableObject {
    @Published var transcribedText: String = ""
    @Published var isRecording: Bool = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("Speech recognition authorized")
                default:
                    print("Speech recognition not authorized: \(status.rawValue)")
                }
            }
        }
    }

    func startRecording() {
        guard !isRecording else { return }

        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        transcribedText = ""

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                DispatchQueue.main.async {
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }
            if error != nil {
                DispatchQueue.main.async {
                    self.stopRecordingInternal()
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isRecording = true
            }
        } catch {
            print("Audio engine failed to start: \(error.localizedDescription)")
        }
    }

    func stopRecording() -> String {
        stopRecordingInternal()
        return transcribedText
    }

    private func stopRecordingInternal() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }
}

// MARK: - OllamaService

class OllamaService: ObservableObject {
    var history: [OllamaMessage] = []

    func send(prompt: String, model: String) async -> String? {
        let userMessage = OllamaMessage(role: "user", content: prompt)
        history.append(userMessage)

        let request = OllamaChatRequest(model: model, messages: history, stream: false)

        guard let url = URL(string: "http://localhost:11434/api/chat") else { return nil }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 120

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            let response = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
            let assistantMessage = response.message
            history.append(assistantMessage)
            return assistantMessage.content
        } catch {
            print("Ollama error: \(error.localizedDescription)")
            return nil
        }
    }

    func clearHistory() {
        history = []
    }
}

// MARK: - TTSManager

class TTSManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking: Bool = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var speechManager = SpeechManager()
    @StateObject private var ollamaService = OllamaService()
    @StateObject private var ttsManager = TTSManager()

    @State private var selectedPersona = "personal"
    @State private var messages: [Message] = []
    @State private var isProcessing = false
    @State private var isHolding = false

    private let personas = ["salesforce", "developer", "content", "personal"]

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar
                .padding(.horizontal)
                .padding(.vertical, 10)

            Divider()

            // Message list
            messageList
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Transcription preview
            if speechManager.isRecording {
                transcriptionPreview
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            // Status indicator
            statusIndicator
                .padding(.horizontal)
                .padding(.top, 8)

            // Hold-to-speak button
            holdToSpeakButton
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 16)
        }
        .frame(minWidth: 640, minHeight: 520)
        .onAppear {
            speechManager.requestPermission()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Text("LOCAL AI")
                .font(.system(.headline, design: .monospaced))
                .bold()

            Spacer()

            Picker("Persona", selection: $selectedPersona) {
                ForEach(personas, id: \.self) { persona in
                    Text(persona).tag(persona)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            Spacer()

            Button("Clear") {
                messages = []
                ollamaService.clearHistory()
                ttsManager.stop()
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if messages.isEmpty && !isProcessing {
                    VStack(spacing: 8) {
                        Text("Hold the button and speak")
                            .font(.system(.title3, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(selectedPersona)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }

                        if isProcessing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            .id("thinking")
                        }
                    }
                    .padding()
                }
            }
            .onChange(of: messages.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: isProcessing) { _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if isProcessing {
                proxy.scrollTo("thinking", anchor: .bottom)
            } else if let lastMessage = messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    private func messageBubble(_ message: Message) -> some View {
        let isUser = message.role == "user"
        return HStack {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.role.uppercased())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isUser ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
                    .cornerRadius(12)
            }
            if !isUser { Spacer(minLength: 60) }
        }
    }

    // MARK: - Transcription Preview

    private var transcriptionPreview: some View {
        HStack {
            Text(speechManager.transcribedText.isEmpty ? "Listening..." : speechManager.transcribedText)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var statusColor: Color {
        if speechManager.isRecording { return .red }
        if isProcessing { return .orange }
        if ttsManager.isSpeaking { return .green }
        return .blue
    }

    private var statusText: String {
        if speechManager.isRecording { return "Listening..." }
        if isProcessing { return "Thinking..." }
        if ttsManager.isSpeaking { return "Speaking..." }
        return "Hold to speak"
    }

    // MARK: - Hold-to-Speak Button

    private var holdToSpeakButton: some View {
        Text(isHolding ? "Release to Send" : "Hold to Speak")
            .font(.system(.body, design: .monospaced))
            .bold()
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(isHolding ? Color.red : Color.blue)
            .cornerRadius(12)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isHolding, !isProcessing else { return }
                        isHolding = true
                        if ttsManager.isSpeaking {
                            ttsManager.stop()
                        }
                        speechManager.startRecording()
                    }
                    .onEnded { _ in
                        guard isHolding else { return }
                        isHolding = false
                        let transcription = speechManager.stopRecording()

                        guard !transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

                        let userText = transcription
                        messages.append(Message(role: "user", content: userText))
                        isProcessing = true

                        Task {
                            let reply = await ollamaService.send(prompt: userText, model: selectedPersona)
                            await MainActor.run {
                                isProcessing = false
                                if let reply = reply {
                                    messages.append(Message(role: "assistant", content: reply))
                                    ttsManager.speak(reply)
                                }
                            }
                        }
                    }
            )
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
