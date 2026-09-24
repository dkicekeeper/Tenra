# Spike: automatic Apple Pay logging via the Shortcuts "Wallet" automation

> Status: **waiting for device data** (probe shipped in DEBUG builds on 2026-09-24).
> Plan: [plans/004-spike-wallet-automation.md](../../../plans/004-spike-wallet-automation.md).
> Probe code: `Tenra/Intents/WalletPaymentProbeIntent.swift`, `Tenra/Services/Intents/WalletPaymentProbeLog.swift` (both `#if DEBUG`, record only, never save a transaction).

## How to run the probe (maintainer, about one week)

1. Install the **Debug** build on "Dkicekeeper 17" from Xcode.
2. Shortcuts → Automation → New Automation → **Wallet** (called "Transaction" before iOS 26) → select all cards → **Run Immediately**.
3. Add the action **"Tenra Wallet Probe (debug)"** and wire Shortcut Input fields:
   - Merchant → `Merchant`
   - Amount → `Amount (text)` **and** `Amount (currency)`
   - Card → `Card`
   - Name → `Name`
4. Pay as usual for about a week. If possible include: one online Apple Pay payment, one foreign-currency payment, one Kaspi QR payment (expected not to trigger).
5. Keep logging manually: the probe saves nothing.
6. Open Settings → Experiments → **Wallet probe (local only)**, select the text of the entries and send it (or fill the sections below).

## Setup used

- iOS version:
- Cards in Wallet (bank, card type):

## Q1. Trigger coverage

Does the automation fire for each card? Contactless in a store? Online Apple Pay? Kaspi QR?

- Evidence:
- Answer:

## Q2. Payload shape

Exact `Amount (text)`; does `Amount (currency)` arrive with a currency code; `Merchant` samples next to the same payment's text in a Kaspi PDF statement; what `Card` and `Name` contain.

- Evidence:
- Answer:

## Q3. Execution

Does it run with the app killed and with the phone locked? Delay between payment and `receivedAt`? Any payments missing from the probe list compared with the bank history (known flakiness report: Apple Developer Forums thread 797233)?

- Evidence:
- Answer:

## Q4. Confirmation behavior

What happens if a real intent calls `requestConfirmation` during an automation run? (`AddExpenseIntent` does whenever the category or account was inferred, which would be every Wallet payment.) Answer from Apple docs/forums if not tested; the probe never asks.

- Evidence:
- Answer:

## Q5. Card → account mapping

Is the `Card` string stable and unique enough to map one Wallet card to one Tenra account?

- Evidence:
- Answer:

## Q6. Duplicates with statement import

For 3-5 payments, compare probe merchant / amount / date with the rows of the imported statement. Candidate dedupe rule: same account, same amount, date within 1 day, same `CategorySuggestionService.normalizedMerchant`.

- Evidence:
- Answer:

## Q7. Currency

For a foreign-currency payment: which amount and currency code arrive?

- Evidence:
- Answer:

## Q8. Categorization hit rate

Share of probe entries with a non-nil `suggested`. Split by `history` = 0 (cold background launch, only the fast path loaded) vs > 0.

- Evidence:
- Answer:

## Q9. Free vs Pro

Options for the maintainer (not decided by the spike): free as a habit builder; Pro as "automatic logging"; free with a monthly cap.

- Answer:

## Q10. Recommendation

GO / NO-GO. For GO, a design sketch:

- `LogWalletPaymentIntent`: parameters, `supportedModes`, amount/currency handling.
- Confirmation policy: e.g. save silently with the suggested category and post a local notification to review, instead of `requestConfirmation`.
- Card → account mapping store and first-run UX.
- Dedupe in `ImportTransactionPreviewView` (pre-unchecked duplicates).
- In-app setup guide (Settings → Siri & Shortcuts section).
- Localized strings in 11 locales.

When this section is filled, delete the two probe files and the Experiments section.
