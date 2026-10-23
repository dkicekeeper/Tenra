//
//  BankNotificationGuideView.swift
//  Tenra
//
//  How to set up the iOS 27 notification automation with "Log a bank notification"
//  (LogBankNotificationIntent, docs/domains/intents.md §7), step by step, and "Check a
//  notification": paste one of the bank's notifications and see what Tenra would record from it
//  (BankNotificationParser, on the phone, nothing saved). Settings → Siri & Shortcuts on iOS 27,
//  and the onboarding's auto-capture step.
//
//  Shortcuts' labels are named in Russian only where the owner's screenshot confirmed them
//  (the Notification variable's «Название», «Подзаголовок», «Текст», «Приложение», «Дата»;
//  2026-10-21); Tenra's action and fields come from the intent's own strings.
//

import SwiftUI

struct BankNotificationGuideView: View {
    /// iOS 27: Shortcuts' notification trigger, and an SDK that knows the version.
    static var isAvailable: Bool {
        #if compiler(>=6.4)
        if #available(iOS 27, *) { return true }
        #endif
        return false
    }

    @Environment(\.openURL) private var openURL
    @State private var page = 0

    var body: some View {
        let pages = self.pages
        let isLast = page >= pages.count - 1
        TabView(selection: $page) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, guidePage in
                GuidePage(page: guidePage, eyebrow: eyebrow(index: index, count: pages.count))
                    .tag(index)
            }
            BankNotificationCheckPage()
                .tag(pages.count)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaBar(edge: .bottom) {
            if page < pages.count {
                DSButton(
                    isLast ? String(localized: "walletSetup.openShortcuts") : String(localized: "onboarding.cta.next"),
                    fullWidth: true
                ) {
                    if isLast {
                        openShortcuts()
                    } else {
                        withAnimation(AppAnimation.contentSpring) { page += 1 }
                    }
                }
                .screenPadding()
                .padding(.bottom, AppSpacing.md)
            }
        }
        .navigationTitle(String(localized: "bankSetup.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: openShortcuts) {
                    Label(String(localized: "walletSetup.openShortcuts"), systemImage: "arrow.up.forward.app")
                }
            }
        }
    }

    private func openShortcuts() {
        if let url = URL(string: "shortcuts://") { openURL(url) }
    }

    /// "Step 2 of 4" for the steps, none for the intro.
    private func eyebrow(index: Int, count: Int) -> String? {
        guard index > 0 else { return nil }
        return String(format: String(localized: "walletSetup.page.step"), index, count - 1)
    }

    // MARK: - Pages

    struct Page: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let blocks: [ArticleBody.Block]
    }

    private var pages: [Page] {
        let action = String(localized: "intent.bankNotification.title")
        let fields = String(
            format: String(localized: "bankSetup.step.fields"),
            String(localized: "intent.bankNotification.parameter.title"),
            String(localized: "intent.bankNotification.parameter.subtitle"),
            String(localized: "intent.bankNotification.parameter.text"),
            String(localized: "intent.bankNotification.parameter.app"),
            String(localized: "intent.bankNotification.parameter.date")
        )
        return [
            Page(
                id: "intro",
                symbol: "bell.badge",
                title: String(localized: "bankSetup.page.intro"),
                blocks: [.paragraph(String(localized: "bankSetup.intro"))]
            ),
            Page(
                id: "trigger",
                symbol: "app.badge",
                title: String(localized: "bankSetup.page.trigger"),
                blocks: [
                    .paragraph(String(localized: "bankSetup.step.trigger")),
                    .note(String(localized: "bankSetup.note.filters")),
                ]
            ),
            Page(
                id: "action",
                symbol: "square.and.pencil",
                title: String(localized: "bankSetup.page.action"),
                blocks: [
                    .paragraph(String(format: String(localized: "bankSetup.step.action"), action)),
                    .paragraph(fields),
                ]
            ),
            Page(
                id: "quiet",
                symbol: "checkmark.circle",
                title: String(localized: "bankSetup.page.quiet"),
                blocks: [.paragraph(String(localized: "bankSetup.step.quiet"))]
            ),
        ]
    }
}

// MARK: - A step

private struct GuidePage: View {
    let page: BankNotificationGuideView.Page
    let eyebrow: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                HeroSymbol(systemImage: page.symbol)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.xl)
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    if let eyebrow {
                        Text(eyebrow)
                            .font(AppTypography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.accent)
                    }
                    Text(page.title)
                        .font(AppTypography.h3)
                        .foregroundStyle(AppColors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ArticleBody(page.blocks)
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }
}

// MARK: - Check a notification

/// The last page: a notification's text pasted in, what the parser finds in it. Nothing is
/// recorded or kept; the text never leaves the phone.
struct BankNotificationCheckPage: View {
    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(String(localized: "bankSetup.page.check"))
                        .font(AppTypography.h3)
                        .foregroundStyle(AppColors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(String(localized: "bankSetup.check.text"))
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                FormSection {
                    TextField(String(localized: "bankSetup.check.placeholder"), text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .font(AppTypography.body)
                        .padding(.vertical, AppSpacing.md)
                }
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var result: some View {
        if let operation = BankNotificationParser.parse(title: "", body: text) {
            switch operation.kind {
            case .expense, .income:
                FormSection(header: String(localized: "bankSetup.check.result")) {
                    UniversalRow(
                        String(localized: "bankSetup.check.kind"),
                        config: .info,
                        accessory: .info(operation.kind == .income
                            ? String(localized: "transactionType.income")
                            : String(localized: "transactionType.expense"))
                    )
                    UniversalRow(
                        String(localized: "transaction.amount"),
                        config: .info,
                        accessory: .amount(operation.amount, currency: operation.currencyCode)
                    )
                    if !operation.counterparty.isEmpty {
                        UniversalRow(
                            String(localized: "bankSetup.check.counterparty"),
                            config: .info,
                            accessory: .info(operation.counterparty)
                        )
                    }
                    if let digits = operation.cardDigits {
                        UniversalRow(
                            String(localized: "bankSetup.check.card"),
                            config: .info,
                            accessory: .info("•• \(digits)")
                        )
                    }
                }
            case .ownTransfer:
                InlineStatusText(message: String(localized: "intent.bankNotification.ownTransfer"), type: .info)
            case .cashWithdrawal:
                InlineStatusText(message: String(localized: "intent.bankNotification.cash"), type: .info)
            }
        } else {
            InlineStatusText(message: String(localized: "bankSetup.check.none"), type: .warning)
        }
    }
}

#Preview {
    NavigationStack {
        BankNotificationGuideView()
    }
}
