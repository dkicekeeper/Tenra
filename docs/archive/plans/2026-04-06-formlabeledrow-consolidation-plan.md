# FormLabeledRow Consolidation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove `FormLabeledRow` by extending `UniversalRow` with `hint` support and migrating all 14 call sites.

**Architecture:** Add optional `hint: String?` parameter to `UniversalRow`. When non-nil, wrap the existing HStack body in a VStack and render hint text below, indented past the icon. All `FormLabeledRow` call sites become `UniversalRow(config: .standard, ...)` with content/trailing ViewBuilders.

**Tech Stack:** SwiftUI, existing design system tokens (AppTypography, AppSpacing, AppColors, AppIconSize)

---

### Task 1: Add `hint` support to UniversalRow

**Files:**
- Modify: `Tenra/Views/Components/Rows/UniversalRow.swift:64-114` (main struct + body)
- Modify: `Tenra/Views/Components/Rows/UniversalRow.swift:303-335` (convenience initializers)

**Step 1: Add `hint` property and update main initializer**

In `UniversalRow` struct, add `hint` property after `leadingIcon`:

```swift
struct UniversalRow<Content: View, Trailing: View>: View {

    // MARK: - Properties

    let config: RowConfiguration
    let leadingIcon: IconConfig?
    let hint: String?

    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing

    // MARK: - Initializer

    init(
        config: RowConfiguration = .standard,
        leadingIcon: IconConfig? = nil,
        hint: String? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.config = config
        self.leadingIcon = leadingIcon
        self.hint = hint
        self.content = content
        self.trailing = trailing
    }
```

**Step 2: Update body to render hint when present**

Replace the body with:

```swift
    // Indent hint to align with label text (past icon + spacing).
    private var hintLeadingPad: CGFloat {
        leadingIcon != nil ? AppIconSize.md + config.spacing : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: hint != nil ? AppSpacing.xs : 0) {
            HStack(spacing: config.spacing) {
                // Leading icon via IconView
                if let iconConfig = leadingIcon {
                    IconView(
                        source: iconConfig.source,
                        style: iconConfig.style
                    )
                }

                // Content expands to fill available space, pushing trailing to the right edge.
                // Using frame(maxWidth:) instead of a Spacer avoids competing spacers when
                // content itself contains an inner Spacer (e.g. infoRow HStack).
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Trailing element
                trailing()
            }

            if let hint {
                Text(hint)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, hintLeadingPad)
                    .padding(.bottom, AppSpacing.xxs)
            }
        }
        .padding(.vertical, config.verticalPadding)
        .padding(.horizontal, config.horizontalPadding)
        .background(config.backgroundColor)
        .clipShape(.rect(cornerRadius: config.cornerRadius))
    }
```

**Step 3: Update convenience initializers to pass `hint: nil`**

In the `where Trailing == EmptyView` extension (~line 303):

```swift
extension UniversalRow where Trailing == EmptyView {
    init(
        config: RowConfiguration = .standard,
        leadingIcon: IconConfig? = nil,
        hint: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.config = config
        self.leadingIcon = leadingIcon
        self.hint = hint
        self.content = content
        self.trailing = { EmptyView() }
    }
}
```

In the `where Content == Text, Trailing == EmptyView` extension (~line 317):

```swift
extension UniversalRow where Content == Text, Trailing == EmptyView {
    init(
        config: RowConfiguration = .standard,
        leadingIcon: IconConfig? = nil,
        hint: String? = nil,
        title: String,
        titleColor: Color = AppColors.textPrimary
    ) {
        self.config = config
        self.leadingIcon = leadingIcon
        self.hint = hint
        self.content = {
            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(titleColor)
        }
        self.trailing = { EmptyView() }
    }
}
```

**Step 4: Build to verify no regressions**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: 0 errors (existing callers pass no `hint`, defaults to `nil`)

**Step 5: Commit**

```
feat(components): add hint support to UniversalRow
```

---

### Task 2: Migrate DepositEditView (4 replacements)

**Files:**
- Modify: `Tenra/Views/Deposits/DepositEditView.swift:53-111`

**Step 1: Replace all 4 FormLabeledRow usages**

Replace lines 53-111 (the two FormSection blocks containing FormLabeledRow) with:

```swift
                    // Bank name + interest rate grouped in one card
                    FormSection(header: String(localized: "deposit.bankDetails", defaultValue: "Bank & Rate")) {
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("building.columns", color: AppColors.textSecondary, size: AppIconSize.md)
                        ) {
                            Text(String(localized: "deposit.bank"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            TextField(
                                String(localized: "deposit.bankNamePlaceholder"),
                                text: $bankName
                            )
                            .multilineTextAlignment(.trailing)
                            .font(AppTypography.bodySmall)
                        }

                        Divider()

                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("percent", color: AppColors.textSecondary, size: AppIconSize.md)
                        ) {
                            Text(String(localized: "deposit.interestRate"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            HStack(spacing: AppSpacing.xs) {
                                TextField("0.0", text: $interestRateText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(AppTypography.bodySmall)
                                    .frame(maxWidth: 80)
                                Text(String(localized: "deposit.rateAnnual"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                    }

                    // Posting day + capitalization grouped in one card
                    FormSection(header: String(localized: "deposit.schedule", defaultValue: "Schedule")) {
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("calendar.badge.clock", color: AppColors.textSecondary, size: AppIconSize.md)
                        ) {
                            Text(String(localized: "deposit.dayOfMonth"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            HStack(spacing: AppSpacing.sm) {
                                Text("\(interestPostingDay)")
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .frame(minWidth: 28, alignment: .trailing)
                                Stepper("", value: $interestPostingDay, in: 1...31)
                                    .labelsHidden()
                                    .fixedSize()
                            }
                        }

                        Divider()

                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("arrow.triangle.2.circlepath", color: AppColors.textSecondary, size: AppIconSize.md),
                            hint: String(localized: "deposit.capitalizationHint")
                        ) {
                            Text(String(localized: "deposit.enableCapitalization"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            Toggle("", isOn: $capitalizationEnabled)
                                .labelsHidden()
                        }
                    }
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: 0 errors

**Step 3: Commit**

```
refactor(deposits): migrate DepositEditView from FormLabeledRow to UniversalRow
```

---

### Task 3: Migrate LoanEditView (4 replacements)

**Files:**
- Modify: `Tenra/Views/Loans/LoanEditView.swift:84-174`

**Step 1: Replace all 4 FormLabeledRow usages**

Replace the loan details FormSection content (lines 84-138) — the 2 FormLabeledRow calls (bank + interest rate):

For bank row (lines 84-94), replace with:
```swift
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("building.columns", color: AppColors.textSecondary, size: AppIconSize.md)
                        ) {
                            Text(String(localized: "loan.bankPlaceholder", defaultValue: "Bank"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            TextField(
                                String(localized: "loan.bankPlaceholder", defaultValue: "Bank name"),
                                text: $bankName
                            )
                            .multilineTextAlignment(.trailing)
                            .font(AppTypography.bodySmall)
                        }
```

For interest rate row (lines 123-137), replace with:
```swift
                            UniversalRow(
                                config: .standard,
                                leadingIcon: .sfSymbol("percent", color: AppColors.textSecondary, size: AppIconSize.md)
                            ) {
                                Text(String(localized: "loan.rateAnnual", defaultValue: "Interest rate"))
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textPrimary)
                            } trailing: {
                                HStack(spacing: AppSpacing.xs) {
                                    TextField("0.0", text: $interestRateText)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .font(AppTypography.bodySmall)
                                        .frame(maxWidth: 80)
                                    Text(String(localized: "loan.rateAnnual", defaultValue: "% annual"))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
```

For term row (lines 143-157), replace with:
```swift
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("clock", color: AppColors.textSecondary, size: AppIconSize.md)
                        ) {
                            Text(String(localized: "loan.termLabel", defaultValue: "Term"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            HStack(spacing: AppSpacing.xs) {
                                TextField("0", text: $termMonthsText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(AppTypography.bodySmall)
                                    .frame(maxWidth: 60)
                                Text(String(localized: "loan.months", defaultValue: "months"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
```

For payment day row (lines 161-174), replace with:
```swift
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("calendar.badge.clock", color: AppColors.textSecondary, size: AppIconSize.md)
                        ) {
                            Text(String(localized: "loan.paymentDay", defaultValue: "Payment day"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            HStack(spacing: AppSpacing.sm) {
                                Text("\(paymentDay)")
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .frame(minWidth: 28, alignment: .trailing)
                                Stepper("", value: $paymentDay, in: 1...31)
                                    .labelsHidden()
                                    .fixedSize()
                            }
                        }
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: 0 errors

**Step 3: Commit**

```
refactor(loans): migrate LoanEditView from FormLabeledRow to UniversalRow
```

---

### Task 4: Migrate LoanRateChangeView (2 replacements)

**Files:**
- Modify: `Tenra/Views/Components/Forms/LoanRateChangeView.swift:33-69`

**Step 1: Replace both FormLabeledRow usages**

For annual rate row (lines 33-48), replace with:
```swift
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("percent", color: AppColors.textSecondary, size: AppIconSize.md)
                        ) {
                            Text(String(localized: "loan.rateLabel", defaultValue: "Annual rate"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            HStack(spacing: AppSpacing.xs) {
                                TextField("0.0", text: $rateText)
                                    .keyboardType(.decimalPad)
                                    .focused($isRateFocused)
                                    .multilineTextAlignment(.trailing)
                                    .font(AppTypography.bodySmall)
                                    .frame(maxWidth: 80)
                                Text(String(localized: "loan.rateAnnual", defaultValue: "% annual"))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
```

For note row (lines 60-69), replace with:
```swift
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("note.text", color: AppColors.textSecondary, size: AppIconSize.md)
                        ) {
                            Text(String(localized: "loan.noteLabel", defaultValue: "Note"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            TextField(
                                String(localized: "loan.notePlaceholder", defaultValue: "Optional"),
                                text: $noteText,
                                axis: .vertical
                            )
                            .lineLimit(1...4)
                            .multilineTextAlignment(.trailing)
                            .font(AppTypography.bodySmall)
                        }
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: 0 errors

**Step 3: Commit**

```
refactor(loans): migrate LoanRateChangeView from FormLabeledRow to UniversalRow
```

---

### Task 5: Migrate LoanPaymentView (2 replacements)

**Files:**
- Modify: `Tenra/Views/Components/Forms/LoanPaymentView.swift:52-79`

**Step 1: Replace both FormLabeledRow usages**

For amount row with hint (lines 52-70), replace with:
```swift
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("banknote", color: AppColors.textSecondary, size: AppIconSize.md),
                            hint: scheduledHint
                        ) {
                            Text(String(localized: "loan.amountLabel", defaultValue: "Amount"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            HStack(spacing: AppSpacing.xs) {
                                TextField(
                                    String(localized: "loan.amountPlaceholder", defaultValue: "Amount"),
                                    text: $amountText
                                )
                                .keyboardType(.decimalPad)
                                .focused($isAmountFocused)
                                .multilineTextAlignment(.trailing)
                                .font(AppTypography.bodySmall)
                                Text(Formatting.currencySymbol(for: account.currency))
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
```

For source account fallback row (lines 75-79), replace with:
```swift
                            UniversalRow(
                                config: .standard,
                                leadingIcon: .sfSymbol("building.columns", color: AppColors.textSecondary, size: AppIconSize.md)
                            ) {
                                Text(String(localized: "loan.sourceAccount", defaultValue: "From account"))
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textPrimary)
                            } trailing: {
                                Text(String(localized: "loan.noSourceAccounts", defaultValue: "No accounts"))
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: 0 errors

**Step 3: Commit**

```
refactor(loans): migrate LoanPaymentView from FormLabeledRow to UniversalRow
```

---

### Task 6: Migrate LoanPayAllView (2 replacements)

**Files:**
- Modify: `Tenra/Views/Components/Forms/LoanPayAllView.swift:68-85`

**Step 1: Replace both FormLabeledRow usages**

For total row (lines 68-75), replace with:
```swift
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("sum", color: AppColors.textSecondary, size: AppIconSize.md)
                        ) {
                            Text(String(localized: "loan.payAllTotal", defaultValue: "Total"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            FormattedAmountText(
                                amount: NSDecimalNumber(decimal: totalPayment).doubleValue,
                                currency: currency,
                                fontSize: AppTypography.bodySmall,
                                color: AppColors.expense
                            )
                        }
```

For source account fallback row (lines 81-85), replace with:
```swift
                            UniversalRow(
                                config: .standard,
                                leadingIcon: .sfSymbol("building.columns", color: AppColors.textSecondary, size: AppIconSize.md)
                            ) {
                                Text(String(localized: "loan.sourceAccount", defaultValue: "From account"))
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textPrimary)
                            } trailing: {
                                Text(String(localized: "loan.noSourceAccounts", defaultValue: "No accounts"))
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: 0 errors

**Step 3: Commit**

```
refactor(loans): migrate LoanPayAllView from FormLabeledRow to UniversalRow
```

---

### Task 7: Migrate LoanEarlyRepaymentView (2 replacements)

**Files:**
- Modify: `Tenra/Views/Components/Forms/LoanEarlyRepaymentView.swift:57-111`

**Step 1: Replace both FormLabeledRow usages**

For amount row with hint (lines 57-75), replace with:
```swift
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("banknote", color: AppColors.textSecondary, size: AppIconSize.md),
                            hint: remainingHint
                        ) {
                            Text(String(localized: "loan.amountLabel", defaultValue: "Amount"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            HStack(spacing: AppSpacing.xs) {
                                TextField(
                                    String(localized: "loan.amountPlaceholder", defaultValue: "Amount"),
                                    text: $amountText
                                )
                                .keyboardType(.decimalPad)
                                .focused($isAmountFocused)
                                .multilineTextAlignment(.trailing)
                                .font(AppTypography.bodySmall)
                                Text(Formatting.currencySymbol(for: account.currency))
                                    .font(AppTypography.bodySmall)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
```

For note row (lines 102-111), replace with:
```swift
                        UniversalRow(
                            config: .standard,
                            leadingIcon: .sfSymbol("note.text", color: AppColors.textSecondary, size: AppIconSize.md)
                        ) {
                            Text(String(localized: "loan.noteLabel", defaultValue: "Note"))
                                .font(AppTypography.bodySmall)
                                .foregroundStyle(AppColors.textPrimary)
                        } trailing: {
                            TextField(
                                String(localized: "loan.notePlaceholder", defaultValue: "Optional"),
                                text: $noteText,
                                axis: .vertical
                            )
                            .lineLimit(1...4)
                            .multilineTextAlignment(.trailing)
                            .font(AppTypography.bodySmall)
                        }
```

**Step 2: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: 0 errors

**Step 3: Commit**

```
refactor(loans): migrate LoanEarlyRepaymentView from FormLabeledRow to UniversalRow
```

---

### Task 8: Delete FormLabeledRow.swift and remove from Xcode project

**Files:**
- Delete: `Tenra/Views/Components/Rows/FormLabeledRow.swift`

**Step 1: Verify no remaining references**

Run: `grep -r "FormLabeledRow" Tenra/ --include="*.swift" -l`
Expected: 0 results (only definition file, which we're deleting)

**Step 2: Delete the file**

```bash
rm Tenra/Views/Components/Rows/FormLabeledRow.swift
```

**Step 3: Remove from Xcode project file**

```bash
# Find the file reference in pbxproj
grep "FormLabeledRow" Tenra.xcodeproj/project.pbxproj
# Remove all lines referencing FormLabeledRow.swift from project.pbxproj
sed -i '' '/FormLabeledRow/d' Tenra.xcodeproj/project.pbxproj
```

**Step 4: Build to verify**

Run: `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30`
Expected: 0 errors

**Step 5: Commit**

```
refactor(components): delete FormLabeledRow, fully replaced by UniversalRow
```

---

### Task 9: Update documentation

**Files:**
- Modify: `CLAUDE.md` (remove FormLabeledRow references)

**Step 1: Update CLAUDE.md**

In the `cardStyle() — Padding Contract` section, remove the line:
```
- **`FormLabeledRow`**: V:12 H:16 — matches `.standard` for consistency inside `FormSection(.card)`
```

And update the UniversalRow hint documentation. In the UI Components section, update the UniversalRow entry to mention hint support.

**Step 2: Commit**

```
docs: remove FormLabeledRow references from CLAUDE.md
```
