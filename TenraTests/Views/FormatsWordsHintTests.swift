//
//  FormatsWordsHintTests.swift
//  TenraTests
//
//  Settings › Formats: the words option's description names the order of its sample. The order
//  comes from the pattern `DateFormatters.day` writes, so kk (whose ICU year template puts the
//  year first, "yyyy 'ж'. d MMMM", while the sample is "3 қараша 2026") reads day first.
//

import Testing
import Foundation
@testable import Tenra

struct FormatsWordsHintTests {

    @Test func kazakhReadsDayFirstLikeItsSample() {
        #expect(FormatsSettingsView.wordsOrderKey(locale: Locale(identifier: "kk_KZ")) == "formats.date.wordsDayFirst")
    }

    @Test func eachLanguageNamesTheOrderItShows() {
        #expect(FormatsSettingsView.wordsOrderKey(locale: Locale(identifier: "ru_KZ")) == "formats.date.wordsDayFirst")
        #expect(FormatsSettingsView.wordsOrderKey(locale: Locale(identifier: "de_DE")) == "formats.date.wordsDayFirst")
        #expect(FormatsSettingsView.wordsOrderKey(locale: Locale(identifier: "es_ES")) == "formats.date.wordsDayFirst")
        #expect(FormatsSettingsView.wordsOrderKey(locale: Locale(identifier: "en_US")) == "formats.date.wordsMonthFirst")
        #expect(FormatsSettingsView.wordsOrderKey(locale: Locale(identifier: "ja_JP")) == "formats.date.wordsYearFirst")
        #expect(FormatsSettingsView.wordsOrderKey(locale: Locale(identifier: "ko_KR")) == "formats.date.wordsYearFirst")
    }
}
