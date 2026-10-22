import SwiftUI
import Speech
import AVFoundation

/// A deliberate, short dictation session. Transcripts remain drafts until the user saves.
@MainActor final class DictationCapture: ObservableObject {
    @Published private(set) var listening = false
    @Published var error: String?
    private let engine = AVAudioEngine()
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var tapInstalled = false
    private var session = UUID()
    private var starting = false

    func start(onText: @escaping (String) -> Void) async {
        guard !starting, !listening else { return }
        starting = true
        let token = UUID(); session = token
        defer { starting = false }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard session == token else { return }
        guard speech == .authorized else { error = "Allow Speech Recognition in iOS Settings → Privacy & Security to dictate. You can still type your task."; return }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard session == token else { return }
        guard microphone else { error = "Allow Microphone access in iOS Settings → Orbit to dictate."; return }
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
            error = "Dictation is unavailable for this language or connection. Try again or type your task."; return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement)
            try audio.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.featureUnsupported) }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapInstalled = true
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                Task { @MainActor in
                    guard let self, self.session == token else { return }
                    if let result { onText(result.bestTranscription.formattedString) }
                    if result?.isFinal == true { self.stop() }
                    else if let failure { self.stop(); self.error = "Dictation stopped: \(failure.localizedDescription). Your draft is still here." }
                }
            }
            engine.prepare(); try engine.start(); listening = true
        } catch { stop(); self.error = "Could not start dictation. Try again or use the keyboard." }
    }
    func stop() {
        session = UUID()
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); recognition?.cancel()
        recognition = nil; request = nil; listening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct DictationButton: View {
    @Binding var text: String
    @StateObject private var capture = DictationCapture()
    @Environment(\.scenePhase) private var phase
    @State private var prefix = ""
    var body: some View {
        Button {
            if capture.listening { capture.stop() }
            else {
                prefix = text.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await capture.start { words in text = prefix.isEmpty ? words : prefix + " " + words } }
            }
        } label: {
            Image(systemName: capture.listening ? "stop.circle.fill" : "mic").font(.system(size: 20))
                .foregroundStyle(capture.listening ? Color.red : Color.secondary).frame(width: 44, height: 44)
        }.accessibilityLabel(capture.listening ? "Stop dictation" : "Dictate task")
            .accessibilityHint("Speak, then review the text before adding")
            .onDisappear { capture.stop() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("orbitCaptureSubmitted"))) { _ in capture.stop() }
            .onChange(of: phase) { _, value in if value == .background { capture.stop() } }
            .alert("Dictation", isPresented: Binding(get: { capture.error != nil }, set: { if !$0 { capture.error = nil } })) {
                Button("OK") { capture.error = nil }
            } message: { Text(capture.error ?? "") }
    }
}
