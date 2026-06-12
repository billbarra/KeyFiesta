import Foundation

enum VolumeLevel: String, CaseIterable {
    case low, medium, high

    var gain: Float {
        switch self {
        case .low: return 0.3
        case .medium: return 0.6
        case .high: return 1.0
        }
    }

    var label: String {
        switch self {
        case .low: return "小"
        case .medium: return "中"
        case .high: return "大"
        }
    }
}

final class Settings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "effectsEnabled": true,
            "soundEnabled": true,
            "volume": VolumeLevel.medium.rawValue,
        ])
    }

    var effectsEnabled: Bool {
        get { defaults.bool(forKey: "effectsEnabled") }
        set { defaults.set(newValue, forKey: "effectsEnabled") }
    }

    var soundEnabled: Bool {
        get { defaults.bool(forKey: "soundEnabled") }
        set { defaults.set(newValue, forKey: "soundEnabled") }
    }

    var volume: VolumeLevel {
        get { VolumeLevel(rawValue: defaults.string(forKey: "volume") ?? "") ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: "volume") }
    }
}
