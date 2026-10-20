//
//  MerchantLogoTests.swift
//  TenraTests
//
//  Pins how a merchant is named and when its row shows a logo: the clean name
//  built from a bank's or Wallet's text, the registry match, and the store that
//  remembers a found logo or its absence.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct MerchantLogoTests {

    // MARK: - Clean name

    @Test("Store numbers go, and text in capitals is re-cased")
    func storeNumbersAndCase() {
        #expect(MerchantName.displayName("GREENMART EXPRESS 123") == "Greenmart Express")
        #expect(MerchantName.displayName("CORNER BAKERY #45") == "Corner Bakery")
    }

    @Test("Legal forms, cities and countries at the ends go, quotes too")
    func legalFormsAndPlaces() {
        #expect(MerchantName.displayName("TOO «GREENMART» ALMATY KZ") == "Greenmart")
        #expect(MerchantName.displayName("ТОО \"Зелёный рынок\"") == "Зелёный рынок")
    }

    @Test("A processor's prefix goes")
    func processorPrefix() {
        #expect(MerchantName.displayName("SQ *BLUE BOTTLE") == "Blue Bottle")
        #expect(MerchantName.displayName("PAYPAL *CORNERSHOP") == "Cornershop")
    }

    @Test("Acronyms stay in capitals, domains go lowercase")
    func acronymsAndDomains() {
        #expect(MerchantName.displayName("KFC 0123") == "KFC")
        #expect(MerchantName.displayName("APPLE.COM/BILL") == "apple.com/bill")
    }

    @Test("A name typed in mixed case keeps its case")
    func mixedCaseKept() {
        #expect(MerchantName.displayName("Corner Bakery 12") == "Corner Bakery")
        #expect(MerchantName.displayName("iHerb") == "iHerb")
    }

    @Test("Text with nothing left after cleaning comes back as it was")
    func nothingLeft() {
        #expect(MerchantName.displayName("  12345 ") == "12345")
        #expect(MerchantName.displayName("KZ") == "KZ")
    }

    @Test("A merchant is searched by text its descriptions contain")
    func searchQuery() {
        #expect(MerchantName.searchQuery("GREENMART CASH&CARRY 123") == "Greenmart Cash&Carry")
        #expect(MerchantName.searchQuery("TOO «SMALL» ALMATY KZ") == "Small")
        // The clean name skips the store number in the middle: its longest word is searched.
        #expect(MerchantName.searchQuery("GREENMART 12 CASH") == "Greenmart")
        #expect(MerchantName.searchQuery("  12345 ") == "12345")
    }

    @Test("A sole proprietor is recognized, so the person's name is never sent")
    func soleProprietor() {
        #expect(MerchantName.isSoleProprietor("ИП ИВАНОВ А.А."))
        #expect(MerchantName.isSoleProprietor("IP IVANOV"))
        #expect(!MerchantName.isSoleProprietor("IPHONE STORE"))
        #expect(!MerchantName.isSoleProprietor("TOO GREENMART"))
    }

    // MARK: - Registry

    @Test("A known brand is found by its name or its first words")
    func registryMatch() {
        #expect(MerchantLogoResolver.registryDomain(forMerchant: "Netflix") == "netflix.com")
        #expect(MerchantLogoResolver.registryDomain(forMerchant: "netflix.com") == "netflix.com")
        #expect(MerchantLogoResolver.registryDomain(forMerchant: "Yandex Go Ride") == "yandex.go")
        #expect(MerchantLogoResolver.registryDomain(forMerchant: "Corner Bakery") == nil)
    }

    // MARK: - Store

    private func makeStore() -> MerchantLogoStore {
        MerchantLogoStore(defaults: UserDefaults(suiteName: "merchant.logo.\(UUID().uuidString)")!)
    }

    @Test("A found logo is shown for every description of the merchant")
    func foundLogo() {
        let store = makeStore()
        store.record(.found("netflix.com"), merchant: "NETFLIX.COM")

        #expect(store.iconSource(forDescription: "Netflix com") == .brandService("netflix.com"))
        #expect(store.iconSource(forDescription: "Corner Bakery") == nil)
    }

    @Test("A merchant without a logo keeps its category icon and is looked up again after 30 days")
    func missingLogo() {
        let store = makeStore()
        let checked = Date(timeIntervalSince1970: 1_790_000_000)
        store.record(.missing, merchant: "Corner Bakery", now: checked)

        #expect(store.iconSource(forDescription: "CORNER BAKERY") == nil)
        #expect(!store.needsLookup(merchant: "Corner Bakery", now: checked.addingTimeInterval(24 * 60 * 60)))
        #expect(store.needsLookup(merchant: "Corner Bakery", now: checked.addingTimeInterval(MerchantLogoStore.recheckInterval + 60)))
    }

    @Test("A found logo is never looked up again; an unknown merchant is")
    func lookupNeeds() {
        let store = makeStore()
        store.record(.found("netflix.com"), merchant: "Netflix")

        #expect(!store.needsLookup(merchant: "NETFLIX", now: Date().addingTimeInterval(MerchantLogoStore.recheckInterval * 2)))
        #expect(store.needsLookup(merchant: "Corner Bakery"))
        #expect(!store.needsLookup(merchant: "12"))
    }

    @Test("A merchant looked up on device only is asked online once it pays with Apple Pay")
    func onlineAfterLocal() {
        let store = makeStore()
        store.record(.missing, merchant: "Corner Bakery", online: false)

        #expect(!store.needsLookup(merchant: "Corner Bakery", online: false))
        #expect(store.needsLookup(merchant: "Corner Bakery", online: true))

        store.record(.missing, merchant: "Corner Bakery", online: true)
        #expect(!store.needsLookup(merchant: "Corner Bakery", online: true))
    }

    // MARK: - The user's choices

    @Test("A picked icon shows for the merchant and a lookup never replaces it")
    func customIcon() {
        let store = makeStore()
        store.setCustomIcon(.sfSymbol("cart"), forMerchant: "CORNER BAKERY 2")

        #expect(store.iconSource(forDescription: "Corner Bakery") == .sfSymbol("cart"))
        #expect(!store.needsLookup(merchant: "Corner Bakery"))

        store.record(.found("bakery.com"), merchant: "Corner Bakery")
        #expect(store.iconSource(forDescription: "Corner Bakery") == .sfSymbol("cart"))

        store.setCustomIcon(nil, forMerchant: "Corner Bakery")
        #expect(store.iconSource(forDescription: "Corner Bakery") == nil)
        #expect(store.needsLookup(merchant: "Corner Bakery"))
    }

    @Test("A name given to the merchant shows for its descriptions; cleared, the bank's text is back")
    func customName() {
        let store = makeStore()
        store.setCustomName("  Пекарня у дома ", forMerchant: "CORNER BAKERY 2")

        #expect(store.customName(forDescription: "Corner Bakery 7") == "Пекарня у дома")
        #expect(store.customName(forDescription: "Greenmart") == nil)

        store.setCustomName("", forMerchant: "Corner Bakery")
        #expect(store.customName(forDescription: "Corner Bakery 7") == nil)
    }

    @Test("Picked icons and names survive a relaunch")
    func choicesPersist() {
        let defaults = UserDefaults(suiteName: "merchant.logo.\(UUID().uuidString)")!
        do {
            let store = MerchantLogoStore(defaults: defaults)
            store.setCustomIcon(.brandService("bakery.com"), forMerchant: "Corner Bakery")
            store.setCustomName("Пекарня", forMerchant: "Corner Bakery")
        }
        let reloaded = MerchantLogoStore(defaults: defaults)
        #expect(reloaded.iconSource(forDescription: "CORNER BAKERY") == .brandService("bakery.com"))
        #expect(reloaded.customName(forDescription: "CORNER BAKERY") == "Пекарня")
    }

    // MARK: - History

    private func tx(_ id: String, _ description: String, _ type: TransactionType = .expense) -> Transaction {
        Transaction(id: id, date: "2026-10-01", description: description, amount: 100, currency: "KZT", type: type, category: "Продукты")
    }

    @Test("Frequent merchants come from expenses and income, most visited first, as first written")
    func frequentMerchants() {
        let history = [
            tx("1", "GREENMART 12"), tx("2", "Greenmart 14"), tx("3", "GREENMART 15"), tx("4", "greenmart"),
            tx("5", "Corner Bakery"), tx("6", "CORNER BAKERY 2"), tx("7", "Corner bakery"),
            tx("8", "Rare Shop"), tx("9", "Rare Shop"),
            tx("10", "Own savings", .internalTransfer), tx("11", "Own savings", .internalTransfer),
            tx("12", "Own savings", .internalTransfer),
            tx("13", "12"), tx("14", "12"), tx("15", "12")
        ]
        let merchants = MerchantLogoResolver.frequentMerchants(in: history, minimumVisits: 3)
        #expect(merchants == ["GREENMART 12", "Corner Bakery"])
    }

    @Test("A row asked before the logo was found gets it afterwards")
    func memoRefreshes() {
        let store = makeStore()
        #expect(store.iconSource(forDescription: "Netflix") == nil)

        store.record(.found("netflix.com"), merchant: "Netflix")
        #expect(store.iconSource(forDescription: "Netflix") == .brandService("netflix.com"))
    }
}
