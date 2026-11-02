//
//  AssetsTests.swift
//  TenraTests
//
//  Assets (docs/domains/assets.md, CoreData v17): the value is the latest valuation by day or
//  the purchase price, the gain and the growth a year come from the purchase price, a sold
//  asset is worth its sale, the person's share and the linked loan give their own money in it.
//  The store totals the held assets at their share, sells and takes a sale back; the
//  repository keeps every field across a new store; a v16 store opens under v17 with its rows.
//

import CoreData
import Foundation
import Testing
@testable import Tenra

@MainActor
@Suite(.serialized, .sharedProcessState)
struct AssetsTests {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeStack() throws -> CoreDataStack {
        let container = NSPersistentContainer(name: "Tenra")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.url = URL(string: "memory://\(UUID().uuidString)")
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return CoreDataStack(container: container)
    }

    /// The flat of the plan: bought in 2018 for 24M, worth 70M now.
    private static func flat(valuations: [AssetValuation]? = nil) -> Asset {
        Asset(
            id: "flat",
            name: "Flat",
            kind: .apartment,
            currency: "KZT",
            purchaseDate: day(2018, 10, 29),
            purchasePrice: 24_000_000,
            valuations: valuations ?? [AssetValuation(id: "v", date: day(2026, 10, 16), value: 70_000_000)]
        )
    }

    // MARK: - AssetValuationMath

    @Test func aFlatBoughtFor24MAndWorth70MGrew192PercentAbout14AYear() {
        let summary = AssetValuationMath.summary(of: Self.flat(), today: Self.day(2026, 10, 29), calendar: Self.calendar)
        #expect(summary.value == 70_000_000)
        #expect(summary.valuedOn == Self.day(2026, 10, 16))
        #expect(summary.gain == 46_000_000)
        #expect(abs((summary.gainPercent ?? 0) - 191.67) < 0.01)
        #expect(abs((summary.multiple ?? 0) - 2.9167) < 0.001)
        // (70 / 24)^(1/8) − 1 ≈ 14.3% over 8 years.
        #expect(abs((summary.annualGrowthPercent ?? 0) - 14.3) < 0.1)
        #expect(summary.loanRemaining == nil)
        #expect(summary.equity == nil)
    }

    @Test func noGrowthAYearBeforeAYearHasPassed() {
        var car = Asset(name: "Car", kind: .vehicle, currency: "KZT", purchaseDate: Self.day(2026, 3, 1), purchasePrice: 10_000_000)
        car.valuations = [AssetValuation(date: Self.day(2026, 9, 1), value: 8_400_000)]
        let summary = AssetValuationMath.summary(of: car, today: Self.day(2026, 10, 29), calendar: Self.calendar)
        #expect(summary.gain == Double(-1_600_000))
        #expect(abs((summary.gainPercent ?? 0) + 16) < 0.0001)
        #expect(summary.annualGrowthPercent == nil)
    }

    @Test func withoutAPurchasePriceThereIsNoGain() {
        let inherited = Asset(
            name: "Country house", kind: .house, currency: "KZT",
            valuations: [AssetValuation(date: Self.day(2026, 3, 3), value: 18_000_000)]
        )
        let summary = AssetValuationMath.summary(of: inherited, today: Self.day(2026, 10, 29), calendar: Self.calendar)
        #expect(summary.value == 18_000_000)
        #expect(summary.gain == nil)
        #expect(summary.gainPercent == nil)
        #expect(summary.multiple == nil)
        #expect(summary.annualGrowthPercent == nil)
    }

    @Test func withoutAValuationTheValueIsThePurchasePrice() {
        let asset = Self.flat(valuations: [])
        let summary = AssetValuationMath.summary(of: asset, today: Self.day(2026, 10, 29), calendar: Self.calendar)
        #expect(summary.value == 24_000_000)
        #expect(summary.valuedOn == Self.day(2018, 10, 29))
        #expect(summary.gain == 0)
    }

    @Test func theLatestValuationIsTheLatestDayNotTheLastAdded() {
        // A valuation added later for an earlier day does not become the value.
        let asset = Self.flat(valuations: [
            AssetValuation(id: "now", date: Self.day(2026, 10, 16), value: 70_000_000),
            AssetValuation(id: "old", date: Self.day(2022, 5, 1), value: 45_000_000),
        ])
        #expect(AssetValuationMath.currentValue(of: asset) == 70_000_000)
        #expect(AssetValuationMath.history(of: asset).map(\.id) == [AssetValuationMath.purchasePointId(asset), "old", "now"])
        #expect(AssetValuationMath.history(of: asset).first?.source == .purchase)
    }

    @Test func aSoldAssetIsWorthItsSaleAndGrewUntilIt() {
        var asset = Self.flat()
        asset.valuations.append(AssetValuation(id: "sale", date: Self.day(2027, 10, 29), value: 75_000_000, source: .sale))
        asset.soldAt = Self.day(2027, 10, 29)
        let summary = AssetValuationMath.summary(of: asset, today: Self.day(2030, 1, 1), calendar: Self.calendar)
        #expect(summary.value == 75_000_000)
        #expect(summary.gain == 51_000_000)
        // (75 / 24)^(1/9) − 1 ≈ 13.5% over the 9 years to the sale, not to 2030.
        #expect(abs((summary.annualGrowthPercent ?? 0) - 13.48) < 0.1)
    }

    @Test func theShareAndTheLoanGiveTheOwnMoneyInIt() {
        var house = Self.flat()
        house.ownershipShare = 0.5
        house.linkedLoanAccountId = "mortgage"
        let summary = AssetValuationMath.summary(
            of: house,
            loan: AssetValuationMath.LoanBalance(amount: 20_000_000, currency: "KZT"),
            today: Self.day(2026, 10, 29),
            calendar: Self.calendar
        )
        #expect(summary.ownedValue == 35_000_000)
        #expect(summary.loanRemaining == 20_000_000)
        #expect(summary.equity == 15_000_000)
        // The gain stays the whole asset's.
        #expect(summary.gain == 46_000_000)
    }

    @Test func theTotalOverTimeCountsEachAssetFromItsFirstPoint() {
        let flat = Self.flat()  // 24M in 2018, 70M in 2026
        var car = Asset(name: "Car", kind: .vehicle, currency: "KZT", purchaseDate: Self.day(2024, 1, 1), purchasePrice: 10_000_000)
        car.ownershipShare = 0.5
        let undated = Asset(name: "Watch", kind: .other, currency: "KZT", purchasePrice: 1_000_000)
        let points = AssetValuationMath.totalHistory(of: [flat, car, undated], calendar: Self.calendar) { amount, _ in amount }
        #expect(points.map(\.date) == [Self.day(2018, 10, 29), Self.day(2024, 1, 1), Self.day(2026, 10, 16)])
        // The watch throughout; the car (half) from 2024 on.
        #expect(points.map(\.value) == [25_000_000, 30_000_000, 76_000_000])
    }

    // MARK: - AssetStore

    @Test func totalsCountHeldAssetsAtTheirShare() async {
        let store = AssetStore(repository: nil)
        var flat = Self.flat()
        flat.ownershipShare = 0.5
        await store.add(flat)
        await store.add(Asset(id: "gift", name: "Watch", kind: .other, currency: "KZT",
                              valuations: [AssetValuation(date: Self.day(2026, 1, 1), value: 1_000_000)]))
        var hidden = Asset(id: "hidden", name: "Garage", kind: .commercial, currency: "KZT", purchasePrice: 5_000_000)
        hidden.includeInNetWorth = false
        await store.add(hidden)

        let totals = store.totals(in: "KZT")
        // 70M × 0.5 + 1M; the garage is left out.
        #expect(totals.value == 36_000_000)
        // Over the flat only (the watch has no price): (70M − 24M) × 0.5 on 12M.
        #expect(totals.gain == 23_000_000)
        #expect(abs((totals.gainPercent ?? 0) - 191.67) < 0.01)
        #expect(store.held(in: .realEstate).map(\.id) == ["flat", "hidden"])
        #expect(store.held(in: .other).map(\.id) == ["gift"])
    }

    @Test func aSaleLeavesTheHeldAssetsAndCanBeTakenBack() async {
        let store = AssetStore(repository: nil)
        await store.add(Self.flat())
        await store.sell(assetId: "flat", price: 72_000_000, date: Self.day(2026, 11, 1))
        #expect(store.held.isEmpty)
        #expect(store.sold.map(\.id) == ["flat"])
        #expect(store.totals(in: "KZT").value == 0)
        #expect(store.asset(id: "flat")?.sale?.value == 72_000_000)

        // A second sale replaces the first.
        await store.sell(assetId: "flat", price: 73_000_000, date: Self.day(2026, 11, 2))
        #expect(store.asset(id: "flat")?.valuations.filter { $0.source == .sale }.count == 1)

        await store.undoSale(assetId: "flat")
        #expect(store.sold.isEmpty)
        #expect(store.asset(id: "flat").flatMap(AssetValuationMath.currentValue) == 70_000_000)

        // Deleting the sale's valuation takes the sale back too.
        await store.sell(assetId: "flat", price: 72_000_000, date: Self.day(2026, 11, 1))
        let saleId = store.asset(id: "flat")?.sale?.id ?? ""
        await store.deleteValuation(id: saleId, from: "flat")
        #expect(store.asset(id: "flat")?.isSold == false)
    }

    /// The owner's car (2026-11-02): bought on 1 June 2021, it counted the repairs of the car
    /// before it. The upkeep is the payments of the days it is held, the sale day included.
    @Test func paymentsCountOnlyWhileTheAssetIsHeld() {
        let local = Calendar.current
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            local.date(from: DateComponents(year: year, month: month, day: day))!
        }
        func payment(_ id: String, _ day: String) -> Transaction {
            Transaction(id: id, date: day, description: "", amount: 10_000, currency: "KZT",
                        type: .expense, category: "Transport", accountId: "card")
        }
        let store = AssetStore(repository: nil)
        store.transactionsOfLink = { _, _ in
            [payment("old car", "2021-05-20"), payment("first", "2021-06-01"),
             payment("later", "2024-03-10"), payment("sale day", "2025-01-15"), payment("after", "2025-02-01")]
        }
        let car = Asset(name: "Car", kind: .vehicle, currency: "KZT",
                        purchaseDate: date(2021, 6, 1), purchasePrice: 9_000_000,
                        expenseLink: AssetCategoryLink(categoryId: "transport", subcategoryIds: ["repair"]),
                        soldAt: date(2025, 1, 15))
        #expect(store.linkedTransactions(of: car).upkeep?.map(\.id) == ["sale day", "later", "first"])

        let undated = Asset(name: "Car", kind: .vehicle, currency: "KZT",
                            expenseLink: AssetCategoryLink(categoryId: "transport"))
        #expect(store.linkedTransactions(of: undated).upkeep?.count == 5)
    }

    /// Payments by hand (v18): one its link counts taken out, one of another category or day
    /// linked in; taking out a payment linked by hand unlinks it; a removed one comes back.
    @Test func paymentsByHand() async {
        func payment(_ id: String, _ day: String, type: TransactionType = .expense) -> Transaction {
            Transaction(id: id, date: day, description: "", amount: 10_000, currency: "KZT",
                        type: type, category: "Transport", accountId: "card")
        }
        let all = [payment("repair", "2024-03-10"), payment("fine", "2024-04-02"),
                   payment("tyres", "2023-11-20"), payment("old", "2019-01-01"), payment("sold parts", "2024-05-01", type: .income)]
        let store = AssetStore(repository: nil)
        store.transactionsOfLink = { _, type in all.filter { $0.type == type && ["repair", "fine"].contains($0.id) } }
        store.transactionsWithIds = { ids in ids.compactMap { id in all.first { $0.id == id } } }
        await store.add(Asset(id: "car", name: "Car", kind: .vehicle, currency: "KZT",
                              expenseLink: AssetCategoryLink(categoryId: "transport")))

        await store.exclude(["fine"], from: "car")
        await store.include(["tyres", "old", "sold parts"], in: "car")
        var car = store.asset(id: "car")!
        #expect(store.linkedTransactions(of: car).upkeep?.map(\.id) == ["repair", "tyres", "old"])
        #expect(store.linkedTransactions(of: car).rent?.map(\.id) == ["sold parts"])
        #expect(store.excludedTransactions(of: car).map(\.id) == ["fine"])

        await store.exclude(["old"], from: "car")
        await store.restore(["fine"], to: "car")
        car = store.asset(id: "car")!
        #expect(car.includedTransactionIds == ["tyres", "sold parts"])
        #expect(car.excludedTransactionIds.isEmpty)
        #expect(store.linkedTransactions(of: car).upkeep?.map(\.id) == ["fine", "repair", "tyres"])
    }

    /// The payments by hand are kept with the asset (v18's `transactionLinksData`).
    @Test func paymentsByHandAreKept() async throws {
        let stack = try makeStack()
        let store = AssetStore(repository: AssetRepository(stack: stack))
        await store.load()
        await store.add(Asset(id: "car", name: "Car", kind: .vehicle, currency: "KZT",
                              excludedTransactionIds: ["fine"], includedTransactionIds: ["tyres"]))
        let reopened = AssetStore(repository: AssetRepository(stack: stack))
        await reopened.load()
        #expect(reopened.asset(id: "car")?.excludedTransactionIds == ["fine"])
        #expect(reopened.asset(id: "car")?.includedTransactionIds == ["tyres"])
    }

    /// A car sold before the next one was bought may keep the same "Transport"; two held at
    /// once may not.
    @Test func carsOneAfterAnotherMayShareTheirUpkeep() {
        let local = Calendar.current
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            local.date(from: DateComponents(year: year, month: month, day: day))!
        }
        typealias Held = AssetValuationMath.HeldPeriod
        let transport = AssetCategoryLink(categoryId: "transport")
        let newCar = Held(start: date(2021, 6, 1), end: nil)
        #expect(!AssetValuationMath.overlaps(transport, held: Held(start: date(2015, 3, 1), end: date(2021, 5, 31)), transport, held: newCar))
        #expect(!AssetValuationMath.overlaps(transport, held: Held(start: date(2015, 3, 1), end: date(2021, 6, 1)), transport, held: newCar))
        #expect(AssetValuationMath.overlaps(transport, held: Held(start: date(2015, 3, 1), end: date(2021, 7, 1)), transport, held: newCar))
        #expect(AssetValuationMath.overlaps(transport, held: Held(start: nil, end: nil), transport, held: newCar))
        #expect(!AssetValuationMath.overlaps(transport, held: Held(start: nil, end: nil), AssetCategoryLink(categoryId: "home"), held: newCar))
    }

    @Test func aDragGivesTheSectionsAssetsItsPlaces() async {
        let store = AssetStore(repository: nil)
        await store.add(Asset(id: "a", name: "A", kind: .apartment, currency: "KZT"))
        await store.add(Asset(id: "car", name: "Car", kind: .vehicle, currency: "KZT"))
        await store.add(Asset(id: "b", name: "B", kind: .house, currency: "KZT"))
        await store.reorder(["b", "a"])
        #expect(store.held(in: .realEstate).map(\.id) == ["b", "a"])
        #expect(store.assets.map(\.id) == ["b", "car", "a"])
    }

    // MARK: - Repository

    @Test func assetsAreKeptAcrossLaunches() async throws {
        let stack = try makeStack()
        let store = AssetStore(repository: AssetRepository(stack: stack))
        await store.load()
        #expect(store.isLoaded)
        #expect(store.assets.isEmpty)
        await store.add(Asset(
            id: "flat",
            name: "Flat",
            kind: .apartment,
            iconSource: .sfSymbol("building.2.fill"),
            currency: "USD",
            purchaseDate: Self.day(2018, 10, 29),
            purchasePrice: 50_000,
            valuations: [AssetValuation(id: "v", date: Self.day(2026, 10, 16), value: 140_000, source: .manual, note: "Listings")],
            depreciationPerYear: 0.05,
            ownershipShare: 0.5,
            linkedLoanAccountId: "mortgage",
            incomeLink: AssetCategoryLink(categoryId: "rent", subcategoryId: "flat-rent"),
            expenseLink: AssetCategoryLink(categoryId: "home"),
            includeInNetWorth: false,
            note: "Second floor",
            createdAt: Self.day(2026, 10, 29)
        ))
        await store.add(Asset(id: "car", name: "Car", kind: .vehicle, currency: "KZT", createdAt: Self.day(2026, 10, 29)))
        await store.sell(assetId: "car", price: 8_000_000, date: Self.day(2026, 10, 30))

        let again = AssetStore(repository: AssetRepository(stack: stack))
        #expect(!again.isLoaded)
        await again.load()
        #expect(again.assets == store.assets)

        await again.delete(id: "flat")
        await again.delete(id: "car")
        #expect(await AssetRepository(stack: stack).all().isEmpty)
    }

    // MARK: - Migration

    /// A store written by v16 opens under the current model by lightweight migration, keeps
    /// its rows and takes assets.
    @Test func aV16StoreOpensWithAssets() throws {
        let momd = try #require(Bundle.main.url(forResource: "Tenra", withExtension: "momd"))
        let v16 = try #require(NSManagedObjectModel(contentsOf: momd.appendingPathComponent("Tenra v16.mom")))
        let current = try #require(NSManagedObjectModel(contentsOf: momd))
        #expect(v16.entitiesByName["AssetEntity"] == nil)
        #expect(current.entitiesByName["AssetEntity"] != nil)
        #expect((try? NSMappingModel.inferredMappingModel(forSourceModel: v16, destinationModel: current)) != nil)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AssetsMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Tenra.sqlite")

        // A v16 store with a goal in it.
        let oldCoordinator = NSPersistentStoreCoordinator(managedObjectModel: v16)
        let oldStore = try oldCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
        let oldContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        oldContext.persistentStoreCoordinator = oldCoordinator
        let goalEntity = try #require(v16.entitiesByName["GoalEntity"])
        try oldContext.performAndWait {
            let goal = NSManagedObject(entity: goalEntity, insertInto: oldContext)
            goal.setValue("g", forKey: "id")
            goal.setValue("Car", forKey: "name")
            goal.setValue(3_000_000.0, forKey: "targetAmount")
            try oldContext.save()
        }
        try oldCoordinator.remove(oldStore)

        // The same file under the current model.
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: current)
        _ = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: url,
            options: [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true]
        )
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let assetEntity = try #require(current.entitiesByName["AssetEntity"])
        try context.performAndWait {
            let goals = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "GoalEntity"))
            #expect(goals.compactMap { $0.value(forKey: "id") as? String } == ["g"])
            let asset = NSManagedObject(entity: assetEntity, insertInto: context)
            asset.setValue("a", forKey: "id")
            asset.setValue("Flat", forKey: "name")
            try context.save()
            #expect(try context.count(for: NSFetchRequest<NSManagedObject>(entityName: "AssetEntity")) == 1)
            // Defaults of a new row: a whole asset, counted in net worth.
            #expect(asset.value(forKey: "ownershipShare") as? Double == 1)
            #expect(asset.value(forKey: "includeInNetWorth") as? Bool == true)
        }
    }

    /// v18 added the payments by hand (`AssetEntity.transactionLinksData`): a v17 store with an
    /// asset opens, the asset keeps everything, and its payments by hand start empty.
    @Test func aV17StoreOpensWithPaymentsByHand() throws {
        let momd = try #require(Bundle.main.url(forResource: "Tenra", withExtension: "momd"))
        let v17 = try #require(NSManagedObjectModel(contentsOf: momd.appendingPathComponent("Tenra v17.mom")))
        let current = try #require(NSManagedObjectModel(contentsOf: momd))
        #expect(v17.entitiesByName["AssetEntity"]?.attributesByName["transactionLinksData"] == nil)
        #expect(current.entitiesByName["AssetEntity"]?.attributesByName["transactionLinksData"] != nil)
        #expect((try? NSMappingModel.inferredMappingModel(forSourceModel: v17, destinationModel: current)) != nil)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AssetLinksMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Tenra.sqlite")

        // A v17 store with a car in it.
        let oldCoordinator = NSPersistentStoreCoordinator(managedObjectModel: v17)
        let oldStore = try oldCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
        let oldContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        oldContext.persistentStoreCoordinator = oldCoordinator
        let oldAssetEntity = try #require(v17.entitiesByName["AssetEntity"])
        try oldContext.performAndWait {
            let car = NSManagedObject(entity: oldAssetEntity, insertInto: oldContext)
            car.setValue("car", forKey: "id")
            car.setValue("Car", forKey: "name")
            car.setValue("vehicle", forKey: "kind")
            try oldContext.save()
        }
        try oldCoordinator.remove(oldStore)

        // The same file under the current model.
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: current)
        _ = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: url,
            options: [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true]
        )
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            let assets = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "AssetEntity"))
            #expect(assets.compactMap { $0.value(forKey: "name") as? String } == ["Car"])
            #expect(assets.first?.value(forKey: "transactionLinksData") == nil)
        }
    }
}
