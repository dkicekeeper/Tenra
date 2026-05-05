# FormLabeledRow Consolidation into UniversalRow

**Date:** 2026-04-06
**Status:** Proposed
**Scope:** Remove `FormLabeledRow`, extend `UniversalRow` with `hint` support

## Problem

`FormLabeledRow` is a near-duplicate of `UniversalRow(config: .standard)`:
- Same HStack layout: icon + label + Spacer + trailing content
- Same padding: V:16 H:16 (matches `.standard` config)
- Same icon rendering via `IconView`
- Only unique feature: optional `hint: String?` displayed below the row

14 usages across 6 files (Deposit/Loan edit forms). All can be expressed as UniversalRow.

## Solution

### 1. Extend UniversalRow with `hint` parameter

Add `hint: String?` to `UniversalRow`:
- Default: `nil` (no visual change for existing callers)
- When non-nil: wrap body in VStack, show hint text below HStack
- Hint indentation: align past icon using `AppIconSize + spacing` calculation (same as FormLabeledRow)

### 2. Migrate 14 call sites

**Translation pattern:**
```swift
// Before
FormLabeledRow(icon: "percent", label: "Rate", hint: "Annual") {
    TextField(...)
}

// After
UniversalRow(
    config: .standard,
    leadingIcon: .sfSymbol("percent", color: AppColors.textSecondary, size: AppIconSize.md),
    hint: "Annual"
) {
    Text("Rate")
        .font(AppTypography.bodySmall)
        .foregroundStyle(AppColors.textPrimary)
} trailing: {
    TextField(...)
}
```

**Files to modify:**
| File | Replacements | Has hint? |
|------|-------------|-----------|
| DepositEditView.swift | 4 | 1 (capitalization) |
| LoanEditView.swift | 4 | 0 |
| LoanRateChangeView.swift | 2 | 0 |
| LoanPaymentView.swift | 2 | 1 (scheduled) |
| LoanPayAllView.swift | 2 | 0 |
| LoanEarlyRepaymentView.swift | 2 | 1 (remaining) |

### 3. Delete FormLabeledRow.swift

Remove file and all preview code.

### 4. Update documentation

- Remove `FormLabeledRow` mention from CLAUDE.md padding contract
- Update `docs/UI_COMPONENTS_GUIDE.md` if it references FormLabeledRow

## Risk Assessment

- **Low risk**: purely mechanical refactor, no behavior change
- **Padding preserved**: UniversalRow `.standard` uses same V:12 H:16 padding
  - Note: FormLabeledRow uses `.padding(AppSpacing.lg)` = V:16 H:16. Need to verify alignment or adjust config.
- **All convenience initializers updated**: existing callers unaffected (hint defaults to nil)
- **Build verification required** after migration

## Decision

Approved for implementation.
