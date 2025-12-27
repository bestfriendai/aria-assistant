import Foundation
import Speech
import AVFoundation

/// On-device wake word detection for "Aria"
/// Target: <20ms detection to feedback
actor WakeWordDetector {
    // MARK: - Configuration

    private let wakeWord = "aria"
    private let confidenceThreshold: Float = 0.7

    // MARK: - Speech Recognition

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Audio

    private var audioEngine: AVAudioEngine?

    // MARK: - State

    private var isListening = false
    private var lastDetectionTime: Date?
    private let debounceInterval: TimeInterval = 1.0 // Prevent rapid triggers

    // MARK: - Callbacks

    private var onWakeWordDetected: (() -> Void)?
    private var onPartialResult: ((String) -> Void)?

    // MARK: - Initialization

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Permissions

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Detection Control

    func startListening(
        onWakeWordDetected: @escaping () -> Void,
        onPartialResult: ((String) -> Void)? = nil
    ) async throws {
        guard !isListening else { return }
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw WakeWordError.recognizerUnavailable
        }

        self.onWakeWordDetected = onWakeWordDetected
        self.onPartialResult = onPartialResult

        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Set up audio engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw WakeWordError.audioEngineFailed
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw WakeWordError.requestCreationFailed
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true // On-device for speed

        // Install audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task {
                await self?.handleRecognitionResult(result, error: error)
            }
        }

        isListening = true
    }

    func stopListening() async {
        guard isListening else { return }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil

        isListening = false
    }

    // MARK: - Recognition Handling

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        guard let result = result else { return }

        let transcription = result.bestTranscription.formattedString.lowercased()

        // Notify partial results
        onPartialResult?(transcription)

        // Check for wake word
        if containsWakeWord(transcription) {
            // Debounce
            if let lastTime = lastDetectionTime,
               Date().timeIntervalSince(lastTime) < debounceInterval {
                return
            }

            lastDetectionTime = Date()

            // Check confidence
            if let segment = result.bestTranscription.segments.last,
               segment.confidence >= confidenceThreshold || segment.confidence == 0 {
                // confidence of 0 means on-device recognition
                onWakeWordDetected?()
            }
        }

        // If final result, restart for continuous listening
        if result.isFinal {
            Task {
                await restartRecognition()
            }
        }
    }

    private func containsWakeWord(_ text: String) -> Bool {
        let words = text.split(separator: " ").map { String($0) }

        // Check last few words for wake word
        let recentWords = words.suffix(5)
        return recentWords.contains { word in
            // Fuzzy match for "aria"
            let normalized = word.lowercased()
            return normalized == wakeWord ||
                   normalized == "area" || // Common misrecognition
                   normalized == "arya" ||
                   normalized == "ariaa"
        }
    }

    private func restartRecognition() async {
        guard isListening else { return }

        // Brief pause before restarting
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Stop and restart
        await stopListening()

        if let callback = onWakeWordDetected {
            try? await startListening(
                onWakeWordDetected: callback,
                onPartialResult: onPartialResult
            )
        }
    }
}

// MARK: - iOS 26+ SpeechAnalyzer Support

@available(iOS 18.0, *)
actor AdvancedWakeWordDetector {
    // This would use the new SpeechAnalyzer API from iOS 26
    // For now, falls back to SFSpeechRecognizer

    private let fallbackDetector = WakeWordDetector()

    func startListening(
        onWakeWordDetected: @escaping () -> Void,
        onPartialResult: ((String) -> Void)? = nil
    ) async throws {
        // In iOS 26+, would use SpeechAnalyzer for <10ms detection
        // For now, use fallback
        try await fallbackDetector.startListening(
            onWakeWordDetected: onWakeWordDetected,
            onPartialResult: onPartialResult
        )
    }

    func stopListening() async {
        await fallbackDetector.stopListening()
    }
}

// MARK: - Errors

enum WakeWordError: Error, LocalizedError {
    case recognizerUnavailable
    case audioEngineFailed
    case requestCreationFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer not available"
        case .audioEngineFailed:
            return "Failed to set up audio engine"
        case .requestCreationFailed:
            return "Failed to create recognition request"
        case .permissionDenied:
            return "Speech recognition permission denied"
        }
    }
}
