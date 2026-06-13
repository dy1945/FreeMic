import Foundation
import Combine

/// UI language preference. `system` follows the OS preferred language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zh, en
    var id: String { rawValue }
}

/// Tiny in-code localization — avoids a `.lproj` / `Bundle.module` resource
/// pipeline (the app bundle is hand-assembled), and lets the user switch
/// language live. Two languages only: Chinese and English.
final class Localization: ObservableObject {
    static let shared = Localization()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }
    private static let key = "uiLanguage"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: raw) ?? .system
    }

    /// True when the effective UI language is English.
    var isEnglish: Bool {
        switch language {
        case .en: return true
        case .zh: return false
        case .system:
            let pref = Locale.preferredLanguages.first ?? "en"
            return !pref.hasPrefix("zh")
        }
    }

    /// Pick the right string for the current language.
    func t(_ zh: String, _ en: String) -> String { isEnglish ? en : zh }
}
