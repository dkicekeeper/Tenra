# Calculator Amount Input — Design Spec

**Date:** 2026-05-31
**Status:** Approved (design); pending implementation plan
**Scope (this iteration):** the expense-by-category add form only (`TransactionAddModal`)

## Goal

Replace the system keyboard for amount entry on the expense-by-category form with a
custom in-app calculator keypad. Users can type arithmetic expressions
(`1200+350`, `1000/3`, `100+10×2`) and the evaluated number becomes the saved amount.

Secondary benefit: with no system keyboard, the keyboard-raise animation disappears —
the input is present the instant the screen appears (the original complaint that started
this work).

## Behaviour (UX)

### Display
- **Large:** the live **result**, formatted exactly like today's amount (grouping,
  currency) — reuses `AmountDigitDisplay`.
- **Small / secondary (above, dimmed):** the raw **expression** (`1 200+350`).
- When the expression is a single number (no operator yet), the small line is hidden —
  it looks like today's plain amount entry.

### Keypad layout (4 columns × 4 rows — matches the user's reference)
```
1  2  3  +
4  5  6  −
7  8  9  ×
,  0  ⌫  ÷
```
- **No `=` key** — the result is always live; "Готово" (the modal's existing nav action)
  saves the already-evaluated number.
- **No `C` key** — **long-press `⌫` clears the whole expression**; a tap deletes the last
  character.
- **`,`** inserts the locale decimal separator into the current operand. Displayed as `,`
  (locale), stored internally as `.`. Ignored if the current operand already has a
  separator (one per operand).
- **Operators** `+ − × ÷` map to `+ - * /` with standard math precedence
  (`×÷` bind tighter than `+−`): `100+10×2 = 120`.

### Edge cases
- **Trailing operator** (`1200+`): result = evaluation of the valid prefix (`1200`).
- **Division by zero / incomplete expression:** keep showing the last valid result; never
  crash, never show `NaN`/`Inf`.
- **Long quotient** (`1000/3`): round the result to 2 decimal places (money).
- **Non-positive / invalid result:** the form's existing save validation handles it
  unchanged — the calculator only computes and displays the number.

## Components (isolated, testable)

### `ExpressionEvaluator` (`Tenra/Utils/`, `nonisolated`)
Pure function: `static func evaluate(_ expression: String) -> Decimal?`.
- Tokenizer + shunting-yard over **`Decimal`** (NOT `NSExpression` — preserves money
  precision and avoids `Double` rounding).
- Operators `+ - * /` with precedence; left-associative.
- Normalises the locale separator to `.` before tokenizing.
- Returns `nil` for empty/garbage/divide-by-zero. For a **trailing operator** it drops the
  dangling operator and evaluates the valid prefix (`1200+` → `1200`).
- No UI, no app state — fully unit-testable.

When `evaluate` returns `nil` mid-typing, the **model retains the last valid result** for
the large display (the result never blanks while the user is still entering an operand),
while the small expression line always shows the live raw text.

### `CalculatorInputModel` (`@Observable`, `@MainActor`)
View-agnostic state machine for the keypad.
- Holds `expression: String` (the display/raw form, with `×÷,`).
- Derives `result: Decimal?` and `resultText: String` via `ExpressionEvaluator`.
- Handles button intents: `digit(_)`, `op(_)`, `separator`, `backspace`, `clear`.
  - Guards: no leading operator, no two operators in a row (replace the pending one),
    one separator per operand.
- The host mirrors `resultText` into the form's `amountText` so downstream validation /
  save are unchanged.

### `CalculatorKeypad` (View)
- 4×4 grid from the layout above, built with `AppSpacing` / `AppColors` tokens.
- Buttons send intents to `CalculatorInputModel`.
- `⌫` supports tap (backspace) and long-press (clear) via the existing gesture patterns.
- Haptics consistent with the rest of the app (`HapticManager.light()` on key press).

### `CalculatorAmountDisplay` (View)
- Large live result (via `AmountDigitDisplay`) + small dimmed expression line.
- Reads from `CalculatorInputModel`.

## Integration & data flow

`TransactionAddModal`:
- Replace `AmountInputView` (system keyboard) with `CalculatorAmountDisplay` inside the
  form, keeping the **currency selector** and **converted-amount** rows as they are.
- Place `CalculatorKeypad` via `.safeAreaInset(edge: .bottom)` so it is pinned to the
  bottom and the form scrolls above it (content never hidden behind the keypad).
- Own the `CalculatorInputModel` as `@State`; mirror `model.resultText →
  coordinator.formData.amountText` on change.
- No focused `TextField` / `@FocusState` for the amount → the system keyboard never rises.

Cleanup: revert the earlier `focusImmediately` flag (`AmountInput` / `AmountInputView` /
`TransactionAddModal`) — it is moot here once the system keyboard is gone, and it had no
measurable effect.

## Out of scope (this iteration)
- Other amount-entry screens (transfer, transaction edit, loan/deposit forms) keep the
  system keyboard. The new components are reusable and can be adopted there later.
- Scientific ops, parentheses, percent — not in the reference layout.

## Testing
- `ExpressionEvaluatorTests` — precedence, separator normalisation, trailing operator,
  divide-by-zero, 2-dp rounding, garbage input.
- `CalculatorInputModelTests` — button sequences → expected `expression` / `result` /
  `resultText`; backspace and clear behaviour; operator/separator guards.
