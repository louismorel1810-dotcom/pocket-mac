import Security
import SwiftUI

enum KeyboardLayout: String, CaseIterable, Identifiable {
    case azerty, qwerty
    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

enum Quality: String, CaseIterable, Identifiable {
    case economy, balanced, maximum
    var id: String { rawValue }

    var title: String {
        switch self {
        case .economy: return "Économie (à distance, 4G)"
        case .balanced: return "Équilibrée"
        case .maximum: return "Maximale (Wi-Fi rapide)"
        }
    }

    func settings(audio: Bool) -> StreamSettings {
        switch self {
        case .economy: return StreamSettings(maxWidth: 1280, fps: 30, bitrate: 2_500_000, audio: audio)
        case .balanced: return StreamSettings(maxWidth: 1920, fps: 30, bitrate: 8_000_000, audio: audio)
        case .maximum: return StreamSettings(maxWidth: 2880, fps: 60, bitrate: 20_000_000, audio: audio)
        }
    }
}

/// Thèmes du MacBook dessiné sous l'écran.
enum Theme: String, CaseIterable, Identifiable {
    case silver, spaceGray, midnight, starlight, sky
    var id: String { rawValue }

    var title: String {
        switch self {
        case .silver: return "Argent"
        case .spaceGray: return "Gris sidéral"
        case .midnight: return "Minuit"
        case .starlight: return "Lumière stellaire"
        case .sky: return "Bleu ciel"
        }
    }

    var deck: Color {
        switch self {
        case .silver: return Color(red: 0.84, green: 0.85, blue: 0.87)
        case .spaceGray: return Color(red: 0.42, green: 0.43, blue: 0.45)
        case .midnight: return Color(red: 0.15, green: 0.17, blue: 0.22)
        case .starlight: return Color(red: 0.89, green: 0.86, blue: 0.80)
        case .sky: return Color(red: 0.62, green: 0.74, blue: 0.84)
        }
    }

    var key: Color { Color(red: 0.11, green: 0.11, blue: 0.12) }
    var keyPressed: Color { Color(red: 0.3, green: 0.3, blue: 0.32) }
    var keyActive: Color { Color.accentColor }
    var keyText: Color { Color(white: 0.92) }

    var trackpad: Color {
        switch self {
        case .midnight, .spaceGray: return deck.opacity(0.75)
        default: return Color.black.opacity(0.08)
        }
    }
}

/// Clés des réglages mémorisés dans le téléphone (utilisées avec @AppStorage).
enum Pref {
    static let theme = "theme"
    static let layout = "layout"
    static let quality = "quality"
    static let audio = "audio"
    static let keySounds = "keySounds"
    static let haptics = "haptics"
    static let invertScroll = "invertScroll"
    static let trackpadSpeed = "trackpadSpeed"
    static let manualHost = "manualHost"
}

/// Le code du Mac est rangé dans le trousseau, pas en clair.
enum Keychain {
    private static let service = "PocketMac"

    static func passcode(for mac: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: mac,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func setPasscode(_ code: String, for mac: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: mac,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(code.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
