import CoreHaptics
import UIKit

@MainActor final class HapticService {
    private var engine: CHHapticEngine?
    private let preferences: Preferences
    init(preferences: Preferences) { self.preferences = preferences }
    func tap(success: Bool = false) {
        guard preferences.haptics else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil {
                engine = try CHHapticEngine()
                engine?.isAutoShutdownEnabled = true
                engine?.resetHandler = { [weak self] in
                    Task { @MainActor in self?.engine = nil }
                }
            }
            try engine?.start()
            let intensity = preferences.hapticLevel.intensity
            let event = CHHapticEvent(eventType: .hapticTransient,
                parameters: [.init(parameterID: .hapticIntensity, value: intensity),
                             .init(parameterID: .hapticSharpness, value: success ? 0.45 : 0.65)], relativeTime: 0)
            let events = success ? [event, CHHapticEvent(eventType: .hapticTransient,
                parameters: [.init(parameterID: .hapticIntensity, value: intensity * 0.7)], relativeTime: 0.12)] : [event]
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine?.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: CGFloat(preferences.hapticLevel.intensity))
        }
    }
}

