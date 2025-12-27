import Foundation
import CoreHaptics
import UIKit

/// Haptic feedback manager for voice interactions
/// Provides immediate tactile feedback (<5ms)
class HapticFeedback {
    static let shared = HapticFeedback()

    private var engine: CHHapticEngine?
    private var supportsHaptics: Bool

    private init() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

        if supportsHaptics {
            setupEngine()
        }
    }

    // MARK: - Setup

    private func setupEngine() {
        do {
            engine = try CHHapticEngine()

            engine?.stoppedHandler = { [weak self] reason in
                self?.restartEngine()
            }

            engine?.resetHandler = { [weak self] in
                self?.restartEngine()
            }

            try engine?.start()
        } catch {
            supportsHaptics = false
        }
    }

    private func restartEngine() {
        try? engine?.start()
    }

    // MARK: - Feedback Types

    /// Wake word detected - subtle tap
    func wakeWordDetected() {
        if supportsHaptics {
            playPattern(.wakeWord)
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    /// Listening started - medium tap
    func listeningStarted() {
        if supportsHaptics {
            playPattern(.listeningStart)
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    /// Processing/thinking - subtle pulse
    func processing() {
        if supportsHaptics {
            playPattern(.processing)
        } else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    /// Response starting - confirmation
    func responseStarted() {
        if supportsHaptics {
            playPattern(.responseStart)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// Action completed successfully
    func success() {
        if supportsHaptics {
            playPattern(.success)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    /// Error or cancellation
    func error() {
        if supportsHaptics {
            playPattern(.error)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    /// Selection changed
    func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    // MARK: - Pattern Definitions

    private enum HapticPattern {
        case wakeWord
        case listeningStart
        case processing
        case responseStart
        case success
        case error

        var events: [CHHapticEvent] {
            switch self {
            case .wakeWord:
                return [
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                        ],
                        relativeTime: 0
                    )
                ]

            case .listeningStart:
                return [
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                        ],
                        relativeTime: 0
                    )
                ]

            case .processing:
                return [
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                        ],
                        relativeTime: 0,
                        duration: 0.1
                    )
                ]

            case .responseStart:
                return [
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                        ],
                        relativeTime: 0
                    ),
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                        ],
                        relativeTime: 0.1
                    )
                ]

            case .success:
                return [
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                        ],
                        relativeTime: 0
                    ),
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
                        ],
                        relativeTime: 0.15
                    )
                ]

            case .error:
                return [
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                        ],
                        relativeTime: 0
                    ),
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                        ],
                        relativeTime: 0.1
                    ),
                    CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                        ],
                        relativeTime: 0.2
                    )
                ]
            }
        }
    }

    private func playPattern(_ pattern: HapticPattern) {
        guard supportsHaptics, let engine = engine else { return }

        do {
            let hapticPattern = try CHHapticPattern(events: pattern.events, parameters: [])
            let player = try engine.makePlayer(with: hapticPattern)
            try player.start(atTime: 0)
        } catch {
            // Fallback to UIKit haptics
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}
