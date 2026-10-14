//
//  VoiceRecognitionLanguage.swift
//  Tenra
//
//  Which language voice input recognizes (docs/domains/voice.md): the choice in Settings →
//  General → Voice language, else the language Tenra shows, so people speak the language they
//  read. The choice exists for those who read one language and speak another (an English
//  iPhone, Russian speech).
//

import Foundation
import Speech

nonisolated enum VoiceRecognitionLanguage {
    /// UserDefaults key; empty or missing means "as in the app".
    static let defaultsKey = "voice.recognitionLanguage"

    /// Recognizer locales for the app's languages, plus Kazakh. Settings offers the ones the
    /// recognizer supports.
    static let candidates = ["ru-RU", "kk-KZ", "en-US", "de-DE", "es-ES", "fr-FR", "tr-TR", "pt-BR", "it-IT", "uk-UA", "ja-JP", "ko-KR"]

    /// The usual region of a language the app shows without one.
    private static let usualRegion = [
        "ru": "RU", "kk": "KZ", "en": "US", "de": "DE", "es": "ES", "fr": "FR",
        "tr": "TR", "pt": "BR", "it": "IT", "uk": "UA", "ja": "JP", "ko": "KR",
    ]

    /// What the recognizer used before the app followed its language.
    static let fallback = "ru-RU"

    /// The locale to recognize now.
    static func current(defaults: UserDefaults = .standard) -> Locale {
        Locale(identifier: identifier(
            stored: defaults.string(forKey: defaultsKey),
            appLanguage: Bundle.main.preferredLocalizations.first,
            region: Locale.current.region?.identifier,
            supported: supportedIdentifiers()
        ))
    }

    /// The choices Settings offers, in `candidates` order.
    static func choices() -> [String] {
        let supported = supportedIdentifiers()
        return candidates.filter { supported.contains($0) }
    }

    static func supportedIdentifiers() -> Set<String> {
        Set(SFSpeechRecognizer.supportedLocales().map { normalized($0.identifier) })
    }

    /// The rule: a stored choice the recognizer supports; else the app's language with its own
    /// region, then the device's region, then its usual one, the first the recognizer supports;
    /// else Russian.
    static func identifier(stored: String?, appLanguage: String?, region: String?, supported: Set<String>) -> String {
        if let stored, !stored.isEmpty, supported.contains(normalized(stored)) { return normalized(stored) }
        guard let appLanguage, !appLanguage.isEmpty else { return fallback }
        let app = normalized(appLanguage)
        if app.contains("-"), supported.contains(app) { return app }
        let language = String(app.prefix { $0 != "-" }).lowercased()
        let options = [region, usualRegion[language]].compactMap { $0.map { "\(language)-\($0.uppercased())" } }
        return options.first(where: supported.contains) ?? fallback
    }

    /// A choice's name in the person's language ("русский (Россия)").
    static func displayName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    private static func normalized(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-")
    }
}
