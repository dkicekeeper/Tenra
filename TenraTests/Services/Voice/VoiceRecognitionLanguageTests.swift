//
//  VoiceRecognitionLanguageTests.swift
//  TenraTests
//
//  Which language voice input recognizes: the Settings choice when the recognizer supports
//  it, else the app's language (its own region, the device's, then the usual one), else
//  Russian as before.
//

import Testing
@testable import Tenra

struct VoiceRecognitionLanguageTests {

    private let supported: Set<String> = ["ru-RU", "en-US", "en-GB", "pt-BR", "de-DE", "uk-UA"]

    private func pick(stored: String? = nil, app: String?, region: String? = nil) -> String {
        VoiceRecognitionLanguage.identifier(stored: stored, appLanguage: app, region: region, supported: supported)
    }

    @Test func theAppLanguageLeads() {
        #expect(pick(app: "ru") == "ru-RU")
        #expect(pick(app: "de", region: "KZ") == "de-DE")
        #expect(pick(app: "uk") == "uk-UA")
        #expect(pick(app: "pt-BR") == "pt-BR")
    }

    @Test func theDeviceRegionWinsWhenSupported() {
        #expect(pick(app: "en", region: "GB") == "en-GB")
        #expect(pick(app: "en", region: "KZ") == "en-US")
    }

    @Test func aChoiceInSettingsOverridesTheAppLanguage() {
        #expect(pick(stored: "ru-RU", app: "en", region: "US") == "ru-RU")
        // An empty choice means "as in the app"; an unsupported one is ignored.
        #expect(pick(stored: "", app: "en") == "en-US")
        #expect(pick(stored: "kk-KZ", app: "de") == "de-DE")
    }

    @Test func russianIsTheFallback() {
        #expect(pick(app: "ja") == "ru-RU")
        #expect(pick(app: nil) == "ru-RU")
    }
}
