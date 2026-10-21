//
//  WalletSetupIllustration.swift
//  Tenra
//
//  The picture of a step of the Wallet automation guide (WalletSetupGuideView): the Shortcuts
//  screen the step is on, drawn as a schema. What the step names is written (Wallet, Tenra's
//  action and fields from the intent's strings, Transaction and its merchant, Show When Run,
//  Set Variable), what it does not is a grey bar, and what to tap is outlined in the accent.
//  Drawn, not a screenshot, so it follows the language and the theme; a screenshot in the asset
//  catalog named `wallet-setup-<step>` (a localized image set for other languages) replaces it.
//
//  Decorative: hidden from VoiceOver, the step's text says the same.
//

import SwiftUI

struct WalletSetupIllustration: View {

    enum Scene: Hashable {
        /// Shortcuts → Automation → +: the list of triggers, Wallet among them.
        case newAutomation
        /// The Wallet trigger: the cards, any category and merchant, run immediately.
        case walletTrigger
        /// Adding an action: Tenra's actions, "Log an Apple Pay payment" among them.
        case actionSearch
        /// Tenra's action with its fields, the given one being filled.
        case field(Field)
        /// The action filled, "Show When Run" off.
        case showWhenRun
        /// Set Variable before the action, its currency code from the variable.
        case setVariable
    }

    /// The action's fields, in the order the guide fills them.
    enum Field: Int, Hashable, CaseIterable {
        case amount, merchant, card, account
    }

    /// The words the picture shows, from the app's strings.
    struct Labels {
        let action: String
        let amount: String
        let merchant: String
        let card: String
        let account: String
        let currency: String
        let transaction: String
        let transactionMerchant: String
        let showWhenRun: String
        let setVariable: String
    }

    let scene: Scene
    let labels: Labels

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            content
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: Metrics.screenWidth, alignment: .leading)
        .background(AppColors.Background.baseAlt, in: .rect(cornerRadius: AppRadius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .strokeBorder(AppColors.Background.neutral2, lineWidth: Metrics.border)
        }
        // A picture: its words stay at the size they are drawn for.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch scene {
        case .newAutomation: newAutomation
        case .walletTrigger: walletTrigger
        case .actionSearch: actionSearch
        case .field(let field): actionCard(filledThrough: field, highlighted: field)
        case .showWhenRun: showWhenRun
        case .setVariable: setVariable
        }
    }

    // MARK: - Scenes

    private var newAutomation: some View {
        Group {
            MockBar(width: Metrics.titleBar, height: Metrics.titleBarHeight)
            searchField(text: nil)
            MockCard {
                row(dot: true) { MockBar(width: Metrics.mediumBar) }
                row(dot: true) { MockBar(width: Metrics.shortBar) }
                row(symbol: "wallet.pass") { Text(verbatim: "Wallet").font(AppTypography.bodySmall) }
                    .highlighted()
                row(dot: true) { MockBar(width: Metrics.mediumBar) }
            }
        }
    }

    private var walletTrigger: some View {
        Group {
            HStack(spacing: AppSpacing.sm) {
                Icon("wallet.pass", size: AppIconSize.md)
                    .foregroundStyle(AppColors.accent)
                Text(verbatim: "Wallet")
                    .font(AppTypography.bodyEmphasis)
            }
            MockCard {
                row(symbol: "creditcard.fill") { MockBar(width: Metrics.longBar) } trailing: { checkmark }
                row(symbol: "creditcard.fill") { MockBar(width: Metrics.mediumBar) } trailing: { checkmark }
            }
            .highlighted()
            MockCard {
                row { MockBar(width: Metrics.shortBar) } trailing: { MockBar(width: Metrics.shortBar) }
                row { MockBar(width: Metrics.shortBar) } trailing: { MockBar(width: Metrics.shortBar) }
            }
            MockCard {
                row { MockBar(width: Metrics.longBar) } trailing: { radio(isOn: true) }
                    .highlighted()
                row { MockBar(width: Metrics.mediumBar) } trailing: { radio(isOn: false) }
            }
        }
    }

    private var actionSearch: some View {
        Group {
            searchField(text: "Tenra")
            MockCard {
                row(appIcon: true) { Text(verbatim: "Tenra").font(AppTypography.bodyEmphasis) }
                row(dot: true) { MockBar(width: Metrics.mediumBar) }
                row(symbol: "wallet.pass") { Text(labels.action).font(AppTypography.bodySmall) }
                    .highlighted()
                row(dot: true) { MockBar(width: Metrics.longBar) }
            }
        }
    }

    private var showWhenRun: some View {
        Group {
            actionCard(filledThrough: .account, highlighted: nil)
            MockCard {
                row { Text(labels.showWhenRun).font(AppTypography.bodySmall) } trailing: {
                    Toggle(isOn: .constant(false)) { EmptyView() }
                        .labelsHidden()
                        .tint(AppColors.accent)
                }
                .highlighted()
            }
        }
    }

    private var setVariable: some View {
        Group {
            MockCard {
                row(symbol: "x.squareroot") {
                    HStack(spacing: AppSpacing.sm) {
                        Text(labels.setVariable).font(AppTypography.bodySmall)
                        token(labels.transaction)
                    }
                }
            }
            .highlighted()
            MockCard {
                row(appIcon: true) { Text(labels.action).font(AppTypography.bodySmall).fontWeight(.semibold) }
                fieldRow(labels.amount) { variableToken }
                fieldRow(labels.currency) { variableToken }
                    .highlighted()
                fieldRow(labels.merchant) { token(labels.transaction, detail: labels.transactionMerchant) }
            }
        }
    }

    /// Tenra's action: the fields up to `filledThrough` filled as the guide says (the account
    /// stays empty), the rest empty, `highlighted` outlined.
    private func actionCard(filledThrough last: Field, highlighted: Field?) -> some View {
        MockCard {
            row(appIcon: true) { Text(labels.action).font(AppTypography.bodySmall).fontWeight(.semibold) }
            ForEach(Field.allCases, id: \.self) { field in
                fieldRow(name(of: field)) {
                    if field.rawValue <= last.rawValue {
                        value(of: field)
                    } else {
                        emptyField
                    }
                }
                .highlighted(field == highlighted)
            }
        }
    }

    // MARK: - Fields

    private func name(of field: Field) -> String {
        switch field {
        case .amount: labels.amount
        case .merchant: labels.merchant
        case .card: labels.card
        case .account: labels.account
        }
    }

    @ViewBuilder
    private func value(of field: Field) -> some View {
        switch field {
        case .amount: token(labels.transaction)
        case .merchant: token(labels.transaction, detail: labels.transactionMerchant)
        case .card: token(labels.transaction, symbol: "creditcard")
        case .account: emptyField
        }
    }

    private func fieldRow<Value: View>(_ name: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Text(name)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: AppSpacing.sm)
            value()
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
    }

    // MARK: - Pieces

    /// A Shortcuts variable: a capsule in the accent.
    private func token(_ text: String, detail: String? = nil, symbol: String? = nil) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Text(text)
            if let detail {
                Icon("chevron.right", size: AppIconSize.xs)
                Text(detail)
            }
            if let symbol {
                Icon("chevron.right", size: AppIconSize.xs)
                Icon(symbol, size: AppIconSize.xs)
            }
        }
        .font(AppTypography.caption)
        .lineLimit(1)
        .foregroundStyle(AppColors.accent)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xxs)
        .background(AppColors.pale(AppColors.accent), in: Capsule())
    }

    /// The variable made by Set Variable.
    private var variableToken: some View {
        Icon("x.squareroot", size: AppIconSize.xs)
            .foregroundStyle(AppColors.accent)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColors.pale(AppColors.accent), in: Capsule())
    }

    /// A field left empty.
    private var emptyField: some View {
        Capsule()
            .strokeBorder(AppColors.Background.neutral2, style: StrokeStyle(lineWidth: Metrics.border, dash: Metrics.dash))
            .frame(width: Metrics.shortBar, height: Metrics.fieldHeight)
    }

    private var checkmark: some View {
        Icon("checkmark", size: AppIconSize.sm)
            .foregroundStyle(AppColors.accent)
    }

    private func radio(isOn: Bool) -> some View {
        Icon(isOn ? "checkmark.circle.fill" : "circle", size: AppIconSize.md)
            .foregroundStyle(isOn ? AppColors.accent : AppColors.textTertiary)
    }

    private func searchField(text: String?) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Icon("magnifyingglass", size: AppIconSize.sm)
                .foregroundStyle(AppColors.textSecondary)
            if let text {
                Text(verbatim: text)
                    .font(AppTypography.bodySmall)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.Background.neutral2, in: Capsule())
    }

    /// A list row with nothing on its trailing edge.
    private func row<Title: View>(
        dot: Bool = false,
        symbol: String? = nil,
        appIcon: Bool = false,
        @ViewBuilder label: () -> Title
    ) -> some View {
        row(dot: dot, symbol: symbol, appIcon: appIcon, label: label) { EmptyView() }
    }

    /// A list row: a grey dot, a symbol in the accent or Tenra's icon, then its text.
    private func row<Title: View, Trailing: View>(
        dot: Bool = false,
        symbol: String? = nil,
        appIcon: Bool = false,
        @ViewBuilder label: () -> Title,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: AppSpacing.sm) {
            if appIcon {
                Image("LaunchIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: AppIconSize.lg, height: AppIconSize.lg)
                    .clipShape(.rect(cornerRadius: AppRadius.xs))
            } else if let symbol {
                Icon(symbol, size: AppIconSize.md)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: AppIconSize.lg)
            } else if dot {
                Circle()
                    .fill(AppColors.Background.neutral2)
                    .frame(width: AppIconSize.md, height: AppIconSize.md)
                    .frame(width: AppIconSize.lg)
            }
            label()
                .lineLimit(1)
            Spacer(minLength: AppSpacing.sm)
            trailing()
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
    }

    fileprivate enum Metrics {
        static let screenWidth: CGFloat = 320
        static let border: CGFloat = 1
        static let dash: [CGFloat] = [3, 3]
        static let barHeight: CGFloat = 8
        static let titleBarHeight: CGFloat = 14
        static let fieldHeight: CGFloat = 20
        static let titleBar: CGFloat = 150
        static let longBar: CGFloat = 120
        static let mediumBar: CGFloat = 90
        static let shortBar: CGFloat = 60
    }
}

// MARK: - Building blocks

/// Text the step does not name.
private struct MockBar: View {
    let width: CGFloat
    var height: CGFloat = WalletSetupIllustration.Metrics.barHeight

    var body: some View {
        Capsule()
            .fill(AppColors.Background.neutral2)
            .frame(width: width, height: height)
    }
}

/// A group of rows, as Shortcuts' lists draw them.
private struct MockCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.Background.baseAltCard, in: .rect(cornerRadius: AppRadius.md))
    }
}

private extension View {
    /// What the step taps: a pale accent with the accent's outline.
    @ViewBuilder
    func highlighted(_ isOn: Bool = true) -> some View {
        if isOn {
            self
                .background(AppColors.pale(AppColors.accent), in: .rect(cornerRadius: AppRadius.md))
                .selectionOutline(true, cornerRadius: AppRadius.md)
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    let labels = WalletSetupIllustration.Labels(
        action: "Log an Apple Pay payment",
        amount: "Amount",
        merchant: "Merchant",
        card: "Card",
        account: "Account",
        currency: "Currency code",
        transaction: "Transaction",
        transactionMerchant: "Merchant",
        showWhenRun: "Show When Run",
        setVariable: "Set Variable"
    )
    ScrollView {
        VStack(spacing: AppSpacing.xl) {
            WalletSetupIllustration(scene: .newAutomation, labels: labels)
            WalletSetupIllustration(scene: .walletTrigger, labels: labels)
            WalletSetupIllustration(scene: .actionSearch, labels: labels)
            WalletSetupIllustration(scene: .field(.merchant), labels: labels)
            WalletSetupIllustration(scene: .showWhenRun, labels: labels)
            WalletSetupIllustration(scene: .setVariable, labels: labels)
        }
        .padding()
    }
}
