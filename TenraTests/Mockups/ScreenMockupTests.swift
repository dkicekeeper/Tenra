//
//  ScreenMockupTests.swift
//  TenraTests
//
//  Renders screens to PNG for the owner to look at before a layout ships (CLAUDE.md, "To check
//  a layout you changed"). A UIWindow with a UIHostingController, drawn by `drawHierarchy`, so
//  glass, navigation bars and scroll views come out as on the phone (ImageRenderer leaves
//  UIKit-backed views out). Runs only where MOCKUP_DIR is set: Actions → Mockups
//  (`.github/workflows/mockups.yml`) sets it per language and uploads the folder. A screen's
//  mockup stays here while its layout is in review; drop it once approved.
//

import Testing
import SwiftUI
import UIKit
@testable import Tenra

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MOCKUP_DIR"] != nil), .serialized)
struct ScreenMockupTests {

    private var directory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["MOCKUP_DIR"] ?? NSTemporaryDirectory())
    }

    // In review: the assets section (docs/archive/plans/plan-assets.md, phases 1 to 3): the Finances card, the
    // list with its hero, an asset's screen and its form, a car losing value by its rule and a
    // garage whose valuation is out of date; a merchant merged from two points of a brand, with a
    // payment linked by hand, and the sheet that combines points (docs/plan-charts-by-day.md,
    // after the device check); the year in review's pages, Ten's message about it and its
    // picture to share (docs/plan-release-1.9.md §3). A new screen in review gets a `@Test` here
    // that calls `render(_:height:_:)`.

    // MARK: - Assets

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    /// A flat that grew, a car that loses 15% a year, a garage without a purchase price valued
    /// in March (out of date), a sold country house: every look of a card.
    private func demoAssets() async -> AssetStore {
        let store = AssetStore(repository: nil)
        await store.add(Asset(
            id: "flat", name: "Flat on Abay", kind: .apartment, currency: "KZT",
            purchaseDate: Self.day(2018, 6, 12), purchasePrice: 24_000_000,
            valuations: [
                AssetValuation(date: Self.day(2021, 5, 1), value: 41_000_000),
                AssetValuation(date: Self.day(2023, 9, 1), value: 58_000_000),
                AssetValuation(date: Self.day(2026, 10, 16), value: 70_000_000, note: "Listings on krisha.kz"),
            ]
        ))
        await store.add(Asset(
            id: "car", name: "Toyota Camry", kind: .vehicle, currency: "KZT",
            purchaseDate: Self.day(2024, 3, 1), purchasePrice: 15_000_000,
            valuations: [AssetValuation(date: Self.day(2026, 9, 2), value: 12_600_000)],
            depreciationPerYear: 0.15
        ))
        await store.add(Asset(
            id: "garage", name: "Garage", kind: .commercial, currency: "KZT",
            valuations: [AssetValuation(date: Self.day(2026, 3, 3), value: 3_500_000)]
        ))
        await store.add(Asset(
            id: "dacha", name: "Country house", kind: .house, currency: "KZT",
            purchaseDate: Self.day(2015, 4, 20), purchasePrice: 6_000_000
        ))
        await store.sell(assetId: "dacha", price: 14_000_000, date: Self.day(2026, 7, 10))
        return store
    }

    @Test func assetsList() async throws {
        let store = await demoAssets()
        let coordinator = AppCoordinator()
        try await render("assets-list", height: 1400) {
            NavigationStack {
                AssetsListView(assetStore: store)
            }
            .environment(coordinator)
            .environment(PremiumManager.shared)
        }
    }

    @Test func assetDetail() async throws {
        let store = await demoAssets()
        let coordinator = AppCoordinator()
        try await render("asset-detail", height: 1500) {
            NavigationStack {
                AssetDetailView(assetStore: store, assetId: "flat")
            }
            .environment(coordinator)
            .environment(coordinator.transactionStore)
            .environment(TimeFilterManager())
            .environment(PremiumManager.shared)
        }
    }

    @Test func assetDetailCar() async throws {
        let store = await demoAssets()
        let coordinator = AppCoordinator()
        try await render("asset-detail-car", height: 1300) {
            NavigationStack {
                AssetDetailView(assetStore: store, assetId: "car")
            }
            .environment(coordinator)
            .environment(coordinator.transactionStore)
            .environment(TimeFilterManager())
            .environment(PremiumManager.shared)
        }
    }

    @Test func assetDetailOutOfDate() async throws {
        let store = await demoAssets()
        let coordinator = AppCoordinator()
        try await render("asset-detail-garage", height: 1100) {
            NavigationStack {
                AssetDetailView(assetStore: store, assetId: "garage")
            }
            .environment(coordinator)
            .environment(coordinator.transactionStore)
            .environment(TimeFilterManager())
            .environment(PremiumManager.shared)
        }
    }

    @Test func assetsCard() async throws {
        let store = await demoAssets()
        try await render("assets-card", height: 300) {
            AssetsCardView(assetStore: store, baseCurrency: "KZT", ratesVersion: 0)
                .screenPadding()
                .frame(maxHeight: .infinity)
                .background(AppColors.Background.base)
        }
    }

    @Test func assetEdit() async throws {
        let store = await demoAssets()
        let flat = try #require(store.asset(id: "flat"))
        try await render("asset-edit") {
            AssetEditView(asset: flat, loanAccounts: [], baseCurrency: "KZT", onSave: { _ in })
        }
    }

    @Test func assetEditCar() async throws {
        let store = await demoAssets()
        let car = try #require(store.asset(id: "car"))
        try await render("asset-edit-car", height: 1100) {
            AssetEditView(asset: car, loanAccounts: [], baseCurrency: "KZT", onSave: { _ in })
        }
    }

    // MARK: - Merchants (the device check of 1.8 build 62)

    /// Two points of one brand over two years, another shop, and a payment entered by hand
    /// linked to the brand; the points merged (MerchantGroupStore).
    private func demoMerchants() async throws -> TransactionStore {
        let repo = UserDefaultsRepository(userDefaults: UserDefaults(suiteName: "mockups.merchants.\(UUID().uuidString)")!)
        let balance = BalanceCoordinator(repository: repo)
        let store = TransactionStore(repository: repo, balanceCoordinator: balance, recurringStore: RecurringStore(repository: repo))
        store.accounts = [Account(id: "card", name: "Card", currency: "KZT", initialBalance: 2_000_000, balance: 2_000_000)]
        store.rebuildAccountById()
        await balance.registerAccounts(store.accounts)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        for month in 0..<20 {
            guard let day = calendar.date(byAdding: .day, value: -month * 30 - 3, to: today) else { continue }
            let date = DateFormatters.dateFormatter.string(from: day)
            let rows = [
                ("ZARA MEGA ALMATY", Double(18_000 + month * 700)),
                ("ZARA DOSTYK PLAZA", Double(9_000 + (month % 4) * 2_500)),
                ("GREENMART 12", 6_400.0)
            ]
            for (index, row) in rows.enumerated() {
                _ = try await store.add(Transaction(
                    id: "m\(month)-\(index)", date: date, description: row.0, amount: row.1,
                    currency: "KZT", type: .expense, category: "", accountId: "card"
                ))
            }
        }
        _ = try await store.add(Transaction(
            id: "manual-coat", date: DateFormatters.dateFormatter.string(from: today), description: "Coat",
            amount: 54_000, currency: "KZT", type: .expense, category: "", accountId: "card"
        ))
        let groups = MerchantGroupStore.shared
        groups.reset()
        groups.merge(["ZARA DOSTYK PLAZA"], into: "ZARA MEGA ALMATY")
        groups.link(transactionIds: ["manual-coat"], toMerchant: "ZARA MEGA ALMATY")
        return store
    }

    @Test func merchantBrand() async throws {
        let store = try await demoMerchants()
        let coordinator = AppCoordinator()
        try await render("merchant-brand", height: 1700) {
            NavigationStack {
                MerchantDetailView(
                    merchant: "ZARA MEGA ALMATY",
                    transactionsViewModel: coordinator.transactionsViewModel,
                    categoriesViewModel: coordinator.categoriesViewModel,
                    accountsViewModel: coordinator.accountsViewModel
                )
            }
            .environment(coordinator)
            .environment(store)
            .environment(TimeFilterManager())
        }
        _ = store
    }

    @Test func merchantMerge() async throws {
        let store = try await demoMerchants()
        MerchantGroupStore.shared.reset()
        try await render("merchant-merge") {
            MerchantMergeView(merchant: "ZARA MEGA ALMATY")
                .environment(store)
        }
        _ = store
    }

    /// The transaction form's merchant (the device check of build 64): the merchant linked,
    /// on top, "No merchant", then the history's merchants.
    @Test func merchantPicker() async throws {
        let store = try await demoMerchants()
        try await render("merchant-picker") {
            NavigationStack {
                MerchantPickerView(current: "ZARA MEGA ALMATY", canClear: true) { _ in }
            }
            .environment(store)
        }
        _ = store
    }

    // MARK: - Feedback ("Write to Ten", docs/domains/assistant.md §6)

    /// Takes the message and says yes: the mockups never reach the server.
    private nonisolated struct AcceptingFeedback: AgentFeedbackTransport {
        func feedback(_ message: AgentFeedbackMessage) async throws {}
    }

    /// Ten's message on Home, as "Ten writes" shows it.
    @Test func feedbackNotice() async throws {
        let notice = try #require(AssistantNotices.feedbackAsk(round: 1, now: Date()))
        try await render("feedback-notice", height: 300) {
            AssistantNoticeCard(notice: notice, onAsk: {}, onHide: {})
                .screenPadding()
                .frame(maxHeight: .infinity)
                .background(AppColors.Background.base)
        }
    }

    /// Ten's chat in the feedback talk, at the step the test leaves it on.
    private func feedbackChat(_ steps: (AssistantViewModel) async -> Void) async -> AssistantViewModel {
        let model = AssistantViewModel(
            conversation: AgentConversation(transport: ScriptedTransport([]), toolkit: FakeToolkit()),
            context: { "" }
        )
        AssistantViewModel.feedbackPause = .zero
        model.startFeedback(source: .notice, transport: AcceptingFeedback())
        await steps(model)
        return model
    }

    private func renderChat(_ name: String, _ model: AssistantViewModel) async throws {
        let coordinator = AppCoordinator()
        try await render(name) {
            NavigationStack {
                AssistantChatView(model: model, wardrobe: coordinator.tenWardrobe)
            }
            .environment(coordinator)
            .environment(PremiumManager.shared)
        }
    }

    // MARK: - Ten's moments (TenMoments, docs/plan-ten-gamification.md §6)

    /// A goal reached: Ten over the app, the screen behind dimmed and blurred.
    @Test func tenMomentGoal() async throws {
        let moment = TenMoment.make(.goalReached(name: "Велосипед"), key: "mockup")
        try await render("ten-moment-goal") {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        SectionHeader("Цели")
                        FormSection {
                            UniversalRow("Велосипед", icon: "bicycle", accessory: .navigation { EmptyView() })
                            UniversalRow("Отпуск", icon: "airplane", accessory: .navigation { EmptyView() })
                            UniversalRow("Подушка безопасности", icon: "umbrella", accessory: .navigation { EmptyView() })
                        }
                    }
                    .screenPadding()
                    .padding(.vertical, AppSpacing.lg)
                }
                .background(AppColors.Background.base)
                MomentOverlay(
                    title: moment.title,
                    message: moment.message,
                    celebrates: moment.celebrates,
                    dismissTitle: String(localized: "moment.dismiss")
                ) {
                    TenMomentHero(moment: moment, accessory: nil, chats: true)
                }
            }
        }
    }

    // MARK: - "Не то" under an answer (AgentReplyReport, docs/domains/assistant.md §7)

    /// An answer of Ten's with "Не то" under it.
    @Test func replyReportButton() async throws {
        let model = AssistantViewModel(
            conversation: AgentConversation(
                transport: ScriptedTransport([[AgentScript.done([AgentScript.render("toolu_1", source: "r1")])]]),
                toolkit: FakeToolkit()
            ),
            context: { "" }
        )
        await model.send("Сколько у меня денег?")
        let coordinator = AppCoordinator()
        try await render("reply-report-button") {
            NavigationStack {
                AssistantChatView(model: model, wardrobe: coordinator.tenWardrobe, reportTransport: AcceptingFeedback())
            }
            .environment(coordinator)
            .environment(PremiumManager.shared)
        }
    }

    /// The sheet: what was wrong, a few words, and what the developer gets.
    @Test func replyReportSheet() async throws {
        let reply = AgentReply(
            blocks: [
                .text("Траты на **кафе выросли** на треть по сравнению с сентябрём."),
                .metric(label: "Кафе, октябрь", source: "r1", path: "total", trendPath: nil),
                .text("Можно поставить лимит на ноябрь."),
            ],
            mood: .concerned,
            suggestions: []
        )
        let exchange = AgentReplyReport.exchange(question: "Почему я так много трачу на кафе?", reply: reply)
        try await render("reply-report-sheet") {
            AssistantReplyReportSheet(exchange: exchange, transport: AcceptingFeedback()) {}
        }
    }

    /// "Write" opens Ten's chat: Ten asks, the two answers sit over the field.
    @Test func feedbackChatAsks() async throws {
        let model = await feedbackChat { _ in }
        try await renderChat("feedback-chat-1-asks", model)
    }

    /// "I like it": Ten asks what else to add.
    @Test func feedbackChatLikes() async throws {
        let model = await feedbackChat { model in
            await model.send(AssistantViewModel.feedbackLike)
        }
        try await renderChat("feedback-chat-2-likes", model)
    }

    /// "Not really", the person's words, and Ten's thanks once they are sent.
    @Test func feedbackChatSent() async throws {
        let model = await feedbackChat { model in
            await model.send(AssistantViewModel.feedbackDislike)
            await model.send("The loan screen is confusing: I cannot find where to add a payment.")
        }
        try await renderChat("feedback-chat-3-sent", model)
    }

    // MARK: - Year in review (docs/plan-release-1.9.md §3)

    /// An invented year: income, twelve months with the busiest in July, five categories, three
    /// merchants, subscriptions, a habit and a holiday as the biggest one-off expense.
    private static let demoReview = YearReview(
        year: 2026,
        currency: "KZT",
        expenses: 4_870_000,
        income: 6_200_000,
        monthlyExpenses: [380_000, 350_000, 420_000, 395_000, 410_000, 520_000,
                          610_000, 390_000, 360_000, 400_000, 335_000, 300_000],
        lastCompleteMonth: 11,
        topCategories: [
            .init(key: "Groceries", label: "Groceries", amount: 1_460_000, share: 0.30),
            .init(key: "Rent", label: "Rent", amount: 1_200_000, share: 0.246),
            .init(key: "Restaurants", label: "Restaurants", amount: 610_000, share: 0.125),
            .init(key: "Transport", label: "Transport", amount: 420_000, share: 0.086),
            .init(key: "Shopping", label: "Shopping", amount: 390_000, share: 0.08),
        ],
        topMerchants: [
            .init(key: "magnum", name: "Magnum", description: "MAGNUM CASH&CARRY", amount: 980_000, visits: 112, usualCategory: "Groceries"),
            .init(key: "small", name: "Small", description: "SMALL 24", amount: 310_000, visits: 64, usualCategory: "Groceries"),
            .init(key: "coffee boom", name: "Coffee Boom", description: "COFFEE BOOM", amount: 145_000, visits: 58, usualCategory: "Restaurants"),
        ],
        subscriptionsTotal: 142_000,
        subscriptions: [
            .init(seriesId: "music", amount: 54_000),
            .init(seriesId: "video", amount: 48_000),
            .init(seriesId: "cloud", amount: 24_000),
            .init(seriesId: "news", amount: 16_000),
        ],
        habit: .init(records: 1_284, days: 301, longestStreak: 47),
        recordsByDay: demoRecordsByDay,
        biggestExpense: .init(amount: 640_000, title: "Air Astana", categoryKey: "Transport", date: "2026-07-14"),
        usedStaleFallback: false
    )

    /// Records on most days of 2026, more on weekends, a quiet week in August.
    private static let demoRecordsByDay: [String: Int] = {
        var days: [String: Int] = [:]
        let calendar = FastDateParser.calendar
        guard var day = FastDateParser.date(from: "2026-01-01") else { return days }
        for index in 0..<334 {
            if index % 9 != 4, !(212...218).contains(index) {
                days[FastDateParser.string(from: day)] = 1 + (index * 7) % 5
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return days
    }()

    private static let demoSeries = [
        RecurringSeries(id: "music", amount: 4_500, currency: "KZT", category: "Shopping", description: "Music",
                        frequency: .monthly, startDate: "2026-01-05", kind: .subscription, iconSource: .sfSymbol("music.note")),
        RecurringSeries(id: "video", amount: 4_000, currency: "KZT", category: "Restaurants", description: "Video",
                        frequency: .monthly, startDate: "2026-01-10", kind: .subscription, iconSource: .sfSymbol("play.tv.fill")),
        RecurringSeries(id: "cloud", amount: 2_000, currency: "KZT", category: "Transport", description: "Cloud",
                        frequency: .monthly, startDate: "2026-01-12", kind: .subscription, iconSource: .sfSymbol("icloud.fill")),
        RecurringSeries(id: "news", amount: 1_400, currency: "KZT", category: "Rent", description: "News",
                        frequency: .monthly, startDate: "2026-02-01", kind: .subscription, iconSource: .sfSymbol("newspaper.fill")),
    ]

    private static let demoCategories = [
        CustomCategory(name: "Groceries", iconSource: .sfSymbol("cart.fill"), colorHex: "#34C759", type: .expense),
        CustomCategory(name: "Rent", iconSource: .sfSymbol("house.fill"), colorHex: "#5856D6", type: .expense),
        CustomCategory(name: "Restaurants", iconSource: .sfSymbol("fork.knife"), colorHex: "#FF9500", type: .expense),
        CustomCategory(name: "Transport", iconSource: .sfSymbol("car.fill"), colorHex: "#007AFF", type: .expense),
        CustomCategory(name: "Shopping", iconSource: .sfSymbol("bag.fill"), colorHex: "#FF2D55", type: .expense),
    ]

    /// Every page of the review, one picture each.
    @Test func yearReviewPages() async throws {
        let pages = YearReviewPage.pages(for: Self.demoReview)
        for (index, page) in pages.enumerated() {
            try await render("year-review-\(index + 1)-\(page.rawValue)") {
                YearReviewView(review: Self.demoReview, categories: Self.demoCategories, series: Self.demoSeries, onPlan: {}, initialPage: index)
            }
        }
    }

    /// Ten's message on Home in the first days of January: the plan for January.
    @Test func januaryPlanNotice() async throws {
        let notice = AssistantNotices.januaryPlan(year: 2027, now: Date())
        try await render("january-plan-notice", height: 300) {
            AssistantNoticeCard(notice: notice, onAsk: {}, onHide: {})
                .screenPadding()
                .frame(maxHeight: .infinity)
                .background(AppColors.Background.base)
        }
    }

    /// Ten's message on Home (Analytics' card is the same NoticeCard with its own words).
    @Test func yearReviewNotice() async throws {
        let notice = AssistantNotices.yearReview(year: 2026, now: Date())
        try await render("year-review-notice", height: 300) {
            AssistantNoticeCard(notice: notice, onAsk: {}, onHide: {})
                .screenPadding()
                .frame(maxHeight: .infinity)
                .background(AppColors.Background.base)
        }
    }

    /// The picture to share, without amounts (the default) and with them.
    @Test func yearReviewShareCard() async throws {
        for showsAmounts in [false, true] {
            try await render("year-review-share-\(showsAmounts ? "amounts" : "plain")", height: 700) {
                YearReviewShareCard(review: Self.demoReview, showsAmounts: showsAmounts, categories: Self.demoCategories)
                    .environment(\.colorScheme, .dark)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.Background.base)
            }
        }
    }

    // MARK: - Rendering

    /// Draws `content` in an iPhone-sized window, in the light and the dark theme, into
    /// `<name>-light.png` and `<name>-dark.png`.
    private func render<Content: View>(
        _ name: String,
        height: CGFloat = 874,
        @ViewBuilder _ content: () -> Content
    ) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
            window.frame = CGRect(x: 0, y: 0, width: 402, height: height)
            window.overrideUserInterfaceStyle = style
            window.rootViewController = UIHostingController(rootView: content())
            window.isHidden = false
            // Lay out, load fonts and let entrance animations settle: polls, not a deadline
            // (CLAUDE.md, Testing).
            for _ in 0..<40 { try await Task.sleep(for: .milliseconds(50)) }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let file = directory.appendingPathComponent("\(name)-\(style == .dark ? "dark" : "light").png")
            try #require(image.pngData()).write(to: file)
            window.isHidden = true
            window.rootViewController = nil
        }
    }
}
