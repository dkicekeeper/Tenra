# Plan 014: Siri does not read out spending while the iPhone is locked

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat a57d5fe4..HEAD -- Tenra/Intents`

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `a57d5fe4`, 2026-09-24

## Why this matters

No App Intent in Tenra declares `authenticationPolicy`, and Apple's default is
`.alwaysAllowed`. Anyone holding a locked iPhone can ask "How much did I spend in Tenra"
and hear the total. The optional in-app lock (Face ID) does not apply to Siri. For an app
positioned as "100% private" this is a leak of financial data.

Decision taken in this plan: the READ intent requires an unlocked device. The WRITE intents
(`LogTransactionIntent`, `AddExpenseIntent`) stay allowed: logging a coffee from the lock screen
is a feature, and the worst case is a junk entry the user can delete. (The Apple Pay automation
spike, plan 004, may run while locked and must keep working.)

## Current state

- `Tenra/Intents/CheckSpendingIntent.swift:38-46`:
  ```swift
  struct CheckSpendingIntent: AppIntent {
      static var title: LocalizedStringResource = "intent.checkSpending.title"
      static var description = IntentDescription("intent.checkSpending.description")
      /// Read-only query answered with a dialog and a snippet — never needs the app in front. ...
      static var supportedModes: IntentModes { .background }
  ```
- SDK: `enum IntentAuthenticationPolicy { case alwaysAllowed, requiresAuthentication, requiresLocalDeviceAuthentication }`
  (verified in the iOS SDK AppIntents swiftinterface). `.requiresAuthentication` asks the user to unlock first.
- `grep -rn authenticationPolicy Tenra` → no matches today.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `xcodebuild build -scheme Tenra -destination 'generic/platform=iOS Simulator' 2>&1 \| grep -E "error:\|BUILD (SUCCEEDED\|FAILED)"` | SUCCEEDED |
| Suite | `xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -only-testing:TenraTests/IntentAuthenticationPolicyTests 2>&1 \| grep -aE "error:\|' failed on\|\*\* TEST (SUCCEEDED\|FAILED)"` | SUCCEEDED |

## Scope

**In scope**: `Tenra/Intents/CheckSpendingIntent.swift`, `TenraTests/Services/Intents/IntentAuthenticationPolicyTests.swift` (create).
**Out of scope**: write intents; the probe intent; Settings copy.

## Git workflow

Commit directly on `main`; do not push. Message: `fix(intents): spending query requires an unlocked device`.

## Steps

1. Add to `CheckSpendingIntent`:
   ```swift
   /// Spending totals are private: Siri must not read them from a locked iPhone.
   static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
   ```
   **Verify**: Build → SUCCEEDED.
2. Test file (plain struct): `#expect(CheckSpendingIntent.authenticationPolicy == .requiresAuthentication)`,
   and pin the deliberate choice for writes: `#expect(LogTransactionIntent.authenticationPolicy == .alwaysAllowed)`,
   `#expect(AddExpenseIntent.authenticationPolicy == .alwaysAllowed)` with a comment explaining why.
   **Verify**: Suite → SUCCEEDED.

## Done criteria

- [ ] Build and suite pass; full TenraTests 0 failed; `plans/README.md` row 014 updated

## STOP conditions

- `IntentAuthenticationPolicy` is not `Equatable` (then assert with `switch`), or the property is already declared elsewhere.

## Maintenance notes

- Device check: lock the phone, ask Siri "How much did I spend in Tenra": Siri asks to unlock first.
- Any future read-only intent (balances, budgets) must declare `.requiresAuthentication` too.
