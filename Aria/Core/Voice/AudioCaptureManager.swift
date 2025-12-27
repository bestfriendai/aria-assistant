import Foundation
import AVFoundation
import Accelerate

/// Manages audio capture for voice input
actor AudioCaptureManager {
    // MARK: - Audio Configuration

    private let sampleRate: Double = 16000
    private let channelCount: AVAudioChannelCount = 1
    private let bufferSize: AVAudioFrameCount = 1024

    // MARK: - Audio Engine

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?

    // MARK: - State

    private var isCapturing = false
    private var audioBuffer: [Float] = []

    // MARK: - Callbacks

    private var onAudioData: ((Data) -> Void)?
    private var onAudioLevel: ((Float) -> Void)?

    // MARK: - Initialization

    func configure() async throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [
            .defaultToSpeaker,
            .allowBluetooth,
            .allowBluetoothA2DP
        ])

        try session.setPreferredSampleRate(sampleRate)
        try session.setPreferredIOBufferDuration(0.005) // 5ms for low latency
        try session.setActive(true)
    }

    // MARK: - Capture Control

    func startCapture(
        onAudioData: @escaping (Data) -> Void,
        onAudioLevel: @escaping (Float) -> Void
    ) async throws {
        guard !isCapturing else { return }

        self.onAudioData = onAudioData
        self.onAudioLevel = onAudioLevel

        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw AudioError.engineCreationFailed
        }

        inputNode = audioEngine.inputNode

        let inputFormat = inputNode!.outputFormat(forBus: 0)
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )!

        // Install tap with format conversion if needed
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        inputNode!.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: inputFormat
        ) { [weak self] buffer, _ in
            Task {
                await self?.processAudioBuffer(buffer, converter: converter, outputFormat: outputFormat)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        isCapturing = true
    }

    func stopCapture() async {
        guard isCapturing else { return }

        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()

        isCapturing = false
        audioBuffer.removeAll()
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter?,
        outputFormat: AVAudioFormat
    ) {
        // Convert to target format if needed
        let processBuffer: AVAudioPCMBuffer
        if let converter = converter {
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * (sampleRate / buffer.format.sampleRate))
            ) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            processBuffer = convertedBuffer
        } else {
            processBuffer = buffer
        }

        guard let channelData = processBuffer.floatChannelData?[0] else { return }

        // Calculate audio level (RMS)
        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(processBuffer.frameLength))
        let level = 20 * log10(max(rms, 0.0001)) // Convert to dB
        let normalizedLevel = max(0, min(1, (level + 50) / 50)) // Normalize to 0-1

        onAudioLevel?(normalizedLevel)

        // Convert to PCM16 data for transmission
        let frameCount = Int(processBuffer.frameLength)
        var pcm16Data = Data(capacity: frameCount * 2)

        for i in 0..<frameCount {
            let sample = max(-1.0, min(1.0, channelData[i]))
            let int16Sample = Int16(sample * Float(Int16.max))
            withUnsafeBytes(of: int16Sample) { bytes in
                pcm16Data.append(contentsOf: bytes)
            }
        }

        onAudioData?(pcm16Data)
    }

    // MARK: - Audio Level

    var currentLevel: Float {
        get async {
            guard isCapturing else { return 0 }
            // Return last computed level
            return 0
        }
    }
}

// MARK: - Audio Playback

actor AudioPlaybackManager {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var mixerNode: AVAudioMixerNode?

    private let sampleRate: Double = 24000 // Gemini output sample rate
    private let channelCount: AVAudioChannelCount = 1

    private var isPlaying = false
    private var audioQueue: [Data] = []

    func configure() async throws {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        mixerNode = AVAudioMixerNode()

        guard let audioEngine = audioEngine,
              let playerNode = playerNode,
              let mixerNode = mixerNode else {
            throw AudioError.engineCreationFailed
        }

        audioEngine.attach(playerNode)
        audioEngine.attach(mixerNode)

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )!

        audioEngine.connect(playerNode, to: mixerNode, format: format)
        audioEngine.connect(mixerNode, to: audioEngine.mainMixerNode, format: format)

        audioEngine.prepare()
        try audioEngine.start()
    }

    func play(_ audioData: Data) async throws {
        guard let audioEngine = audioEngine,
              let playerNode = playerNode else {
            throw AudioError.notConfigured
        }

        // Convert PCM16 data to float buffer
        let sampleCount = audioData.count / 2
        var floatSamples = [Float](repeating: 0, count: sampleCount)

        audioData.withUnsafeBytes { buffer in
            let int16Buffer = buffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                floatSamples[i] = Float(int16Buffer[i]) / Float(Int16.max)
            }
        }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else {
            throw AudioError.bufferCreationFailed
        }

        buffer.frameLength = AVAudioFrameCount(sampleCount)
        floatSamples.withUnsafeBufferPointer { ptr in
            buffer.floatChannelData?[0].update(from: ptr.baseAddress!, count: sampleCount)
        }

        if !audioEngine.isRunning {
            try audioEngine.start()
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }

        playerNode.scheduleBuffer(buffer) {
            // Buffer finished playing
        }
    }

    func stop() async {
        playerNode?.stop()
        audioQueue.removeAll()
        isPlaying = false
    }

    func setVolume(_ volume: Float) async {
        mixerNode?.outputVolume = volume
    }
}

// MARK: - Errors

enum AudioError: Error, LocalizedError {
    case engineCreationFailed
    case notConfigured
    case bufferCreationFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .engineCreationFailed:
            return "Failed to create audio engine"
        case .notConfigured:
            return "Audio system not configured"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .permissionDenied:
            return "Microphone permission denied"
        }
    }
}
