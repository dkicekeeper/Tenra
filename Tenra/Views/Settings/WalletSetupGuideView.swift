//
//  WalletSetupGuideView.swift
//  Tenra
//
//  How to set up the Shortcuts Wallet automation with "Log an Apple Pay payment"
//  (LogWalletPaymentIntent, docs/domains/intents.md §6), step by step. Settings → Siri &
//  Shortcuts. One step per page, swiped or moved on with Next: the picture of the Shortcuts
//  screen the step is on (WalletSetupIllustration, or a screenshot `wallet-setup-<id>` from the
//  asset catalog when there is one), "Step N of M", a title and what to do. Shortcuts opens from
//  the toolbar on every page and from the button of the last one.
//
//  Shortcuts' own labels are named only where the owner's screenshot confirmed them in Russian
//  ("Транзакция", its "Продавец", "Любая категория", "Любой продавец", "Показать при запуске";
//  2026-10-20); the rest is described. Tenra's action and field names come from the intent's
//  own strings, so the guide always matches what Shortcuts shows for them.
//

import SwiftUI

struct WalletSetupGuideView: View {
    @Environment(\.openURL) private var openURL
    @State private var page = 0

    var body: some View {
        let steps = self.steps
        let isLast = page >= steps.count - 1
        TabView(selection: $page) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                StepPage(step: step, eyebrow: eyebrow(for: step, in: steps), labels: labels)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaBar(edge: .bottom) {
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
        .navigationTitle(String(localized: "walletSetup.title"))
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

    /// "Step 3 of 8" for the steps, "Optional" for the currency one, none for the intro.
    private func eyebrow(for step: Step, in steps: [Step]) -> String? {
        guard step.illustration != nil else { return nil }
        if step.isOptional { return String(localized: "walletSetup.page.optional") }
        let numbered = steps.filter { $0.illustration != nil && !$0.isOptional }
        guard let number = numbered.firstIndex(where: { $0.id == step.id }) else { return nil }
        return String(
            format: String(localized: "walletSetup.page.step"),
            number + 1, numbered.count
        )
    }

    // MARK: - Steps

    /// One page of the guide.
    struct Step: Identifiable {
        /// Also names the screenshot that can replace the drawing: `wallet-setup-<id>`.
        let id: String
        let title: String
        /// Inline Markdown (**bold**).
        let text: String
        var note: String?
        var isOptional = false
        /// `nil` for the intro, which shows the Wallet symbol.
        let illustration: WalletSetupIllustration.Scene?
    }

    private var labels: WalletSetupIllustration.Labels {
        WalletSetupIllustration.Labels(
            action: String(localized: "intent.walletPayment.title"),
            amount: String(localized: "intent.walletPayment.parameter.amount"),
            merchant: String(localized: "intent.walletPayment.parameter.merchant"),
            card: String(localized: "intent.walletPayment.parameter.card"),
            account: String(localized: "intent.walletPayment.parameter.account"),
            currency: String(localized: "intent.walletPayment.parameter.currency"),
            transaction: String(localized: "walletSetup.mock.transaction"),
            transactionMerchant: String(localized: "walletSetup.mock.merchant"),
            showWhenRun: String(localized: "walletSetup.mock.showWhenRun"),
            setVariable: String(localized: "walletSetup.mock.setVariable")
        )
    }

    private var steps: [Step] {
        let labels = self.labels
        let oldAction = String(localized: "intent.addExpense.title")
        return [
            Step(
                id: "intro",
                title: String(localized: "walletSetup.page.intro"),
                text: String(localized: "walletSetup.intro"),
                illustration: nil
            ),
            Step(
                id: "trigger",
                title: String(localized: "walletSetup.page.trigger"),
                text: String(localized: "walletSetup.step.open"),
                illustration: .newAutomation
            ),
            Step(
                id: "cards",
                title: String(localized: "walletSetup.page.cards"),
                text: String(localized: "walletSetup.step.cards"),
                illustration: .walletTrigger
            ),
            Step(
                id: "action",
                title: String(localized: "walletSetup.page.action"),
                text: String(format: String(localized: "walletSetup.step.action"), labels.action),
                note: String(format: String(localized: "walletSetup.note.oldAction"), oldAction, labels.action),
                illustration: .actionSearch
            ),
            Step(
                id: "amount",
                title: labels.amount,
                text: String(format: String(localized: "walletSetup.step.amount"), labels.amount),
                illustration: .field(.amount)
            ),
            Step(
                id: "merchant",
                title: labels.merchant,
                text: String(format: String(localized: "walletSetup.step.merchant"), labels.merchant),
                illustration: .field(.merchant)
            ),
            Step(
                id: "card",
                title: labels.card,
                text: String(format: String(localized: "walletSetup.step.card"), labels.card),
                illustration: .field(.card)
            ),
            Step(
                id: "account",
                title: labels.account,
                text: String(format: String(localized: "walletSetup.step.account"), labels.account),
                illustration: .field(.account)
            ),
            Step(
                id: "quiet",
                title: String(localized: "walletSetup.page.quiet"),
                text: String(localized: "walletSetup.step.quiet"),
                illustration: .showWhenRun
            ),
            Step(
                id: "currency",
                title: String(localized: "walletSetup.currency"),
                text: String(format: String(localized: "walletSetup.currency.text"), labels.currency),
                isOptional: true,
                illustration: .setVariable
            )
        ]
    }
}

// MARK: - Page

/// The picture on top, then "Step N of M", the title and the text. Scrolls when the text is
/// long (large Dynamic Type), under the Next button with the soft edge.
private struct StepPage: View {
    let step: WalletSetupGuideView.Step
    let eyebrow: String?
    let labels: WalletSetupIllustration.Labels

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                picture
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    if let eyebrow {
                        Text(eyebrow)
                            .font(AppTypography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.accent)
                    }
                    Text(step.title)
                        .font(AppTypography.h3)
                        .foregroundStyle(AppColors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ArticleBody(blocks)
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    private var blocks: [ArticleBody.Block] {
        var blocks: [ArticleBody.Block] = [.paragraph(step.text)]
        if let note = step.note { blocks.append(.note(note)) }
        return blocks
    }

    @ViewBuilder
    private var picture: some View {
        if let screenshot = UIImage(named: "wallet-setup-\(step.id)") {
            Image(uiImage: screenshot)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: StepPageMetrics.screenshotHeight)
                .clipShape(.rect(cornerRadius: AppRadius.xl))
                .accessibilityHidden(true)
        } else if let scene = step.illustration {
            WalletSetupIllustration(scene: scene, labels: labels)
        } else {
            HeroSymbol(systemImage: "wallet.pass")
                .padding(.vertical, AppSpacing.xl)
        }
    }
}

private enum StepPageMetrics {
    /// A screenshot fits this height, leaving room for the text on a small iPhone.
    static let screenshotHeight: CGFloat = 420
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WalletSetupGuideView()
    }
}
