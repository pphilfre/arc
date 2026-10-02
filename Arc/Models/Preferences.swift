import SwiftUI
import Observation

enum Appearance: String, CaseIterable, Identifiable {
    case auto = "Auto", light = "Light", dark = "Dark"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self { case .auto: nil; case .light: .light; case .dark: .dark }
    }
}
enum Accent: String, CaseIterable, Identifiable {
    case blue = "Blue", purple = "Purple", green = "Green", orange = "Orange", pink = "Pink", mono = "Mono"
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .blue: Color(red: 0.12, green: 0.43, blue: 1)
        case .purple: Color(red: 0.55, green: 0.31, blue: 0.95)
        case .green: Color(red: 0.12, green: 0.68, blue: 0.42)
        case .orange: .orange
        case .pink: .pink
        case .mono: .primary
        }
    }
}
enum SpeedUnit: String, CaseIterable, Identifiable {
    case mph, kmh = "km/h"
    var id: String { rawValue }
    var unit: UnitSpeed { self == .mph ? .milesPerHour : .kilometersPerHour }
    func speed(_ metersPerSecond: Double) -> Int {
        guard metersPerSecond.isFinite, metersPerSecond < 1000 else { return 0 }
        return Int(Measurement(value: max(0, metersPerSecond), unit: UnitSpeed.metersPerSecond).converted(to: unit).value.rounded())
    }
    func distance(_ meters: Double) -> String {
        if self == .mph {
            return meters < 160.934 ? "\(Int((meters * 3.28084).rounded())) ft" : String(format: "%.1f mi", meters / 1609.344)
        }
        return meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000)
    }
}
enum VoiceMode: String, CaseIterable, Identifiable {
    case full = "Full directions", alerts = "Alerts only", muted = "Muted"
    var id: String { rawValue }
}
enum HapticLevel: String, CaseIterable, Identifiable {
    case subtle = "Subtle", medium = "Medium", strong = "Strong"
    var id: String { rawValue }
    var intensity: Float { switch self { case .subtle: 0.25; case .medium: 0.55; case .strong: 0.9 } }
}

@MainActor @Observable final class Preferences {
    private let defaults: UserDefaults
    var appearance: Appearance { didSet { save(appearance.rawValue, "appearance") } }
    var accent: Accent { didSet { save(accent.rawValue, "accent") } }
    var units: SpeedUnit { didSet { save(units.rawValue, "units") } }
    var voice: VoiceMode { didSet { save(voice.rawValue, "voice") } }
    var hapticLevel: HapticLevel { didSet { save(hapticLevel.rawValue, "hapticLevel") } }
    var haptics: Bool { didSet { defaults.set(haptics, forKey: "haptics") } }
    var satellite: Bool { didSet { defaults.set(satellite, forKey: "satellite") } }
    var buildings: Bool { didSet { defaults.set(buildings, forKey: "buildings") } }
    var traffic: Bool { didSet { defaults.set(traffic, forKey: "traffic") } }
    var drivingPOIs: Bool { didSet { defaults.set(drivingPOIs, forKey: "drivingPOIs") } }
    var avoidMotorways: Bool { didSet { defaults.set(avoidMotorways, forKey: "avoidMotorways") } }
    var avoidTolls: Bool { didSet { defaults.set(avoidTolls, forKey: "avoidTolls") } }
    var avoidFerries: Bool { didSet { defaults.set(avoidFerries, forKey: "avoidFerries") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .auto
        accent = Accent(rawValue: defaults.string(forKey: "accent") ?? "") ?? .blue
        units = SpeedUnit(rawValue: defaults.string(forKey: "units") ?? "") ?? .mph
        voice = VoiceMode(rawValue: defaults.string(forKey: "voice") ?? "") ?? .full
        hapticLevel = HapticLevel(rawValue: defaults.string(forKey: "hapticLevel") ?? "") ?? .medium
        haptics = (defaults.object(forKey: "haptics") as? Bool) ?? true
        satellite = defaults.bool(forKey: "satellite")
        buildings = defaults.bool(forKey: "buildings")
        traffic = (defaults.object(forKey: "traffic") as? Bool) ?? true
        drivingPOIs = defaults.bool(forKey: "drivingPOIs")
        avoidMotorways = defaults.bool(forKey: "avoidMotorways")
        avoidTolls = defaults.bool(forKey: "avoidTolls")
        avoidFerries = defaults.bool(forKey: "avoidFerries")
    }
    private func save(_ value: String, _ key: String) { defaults.set(value, forKey: key) }
}
