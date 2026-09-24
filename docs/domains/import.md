# Document Import

Bank statements (PDF) and paper receipts (camera) both land in the same
three-stage pipeline. Read this before touching anything in
`Tenra/Services/Import/`.

## Pipeline

| Stage | Types | Notes |
|---|---|---|
| Acquisition | `DocumentPicker`, `DocumentScannerView` | PDF file or VisionKit camera scan. |
| Extraction | `PDFTextLayerExtractor`, `VisionDocumentExtractor` | Both produce `DocumentSnapshot`. Text-layer PDFs skip OCR entirely. |
| Interpretation | `ColumnRoleResolver`, `IntelligentColumnRoleResolver`, `StatementInterpreter`, `ReceiptInterpreter` | Consume only `DocumentSnapshot`. |

`DocumentImportService` is the single orchestrator. `PDFService` is now only a
page rasteriser.

## Rules

1. **`DocumentSnapshot` is the seam.** Nothing in interpretation may import
   Vision, PDFKit, or UIKit. This is what makes the parsers unit-testable.
2. **Apple Intelligence is never required.** Every path must produce a result
   when `IntelligenceAvailability.status` is not `.available`. Roughly half the
   install base has no Apple Intelligence.
3. **Apple Intelligence infers layout, not values, for statements.** It receives
   the header plus two sample rows and returns column indices. All amounts are
   then parsed deterministically. Do not switch to per-row LLM extraction: a
   200-row statement exceeds the context window, and a model re-typing amounts
   can corrupt them.
4. **Receipts are the opposite case.** The payload is small and layouts vary
   wildly, so `ReceiptInterpreter` asks the model for the values directly, with
   `heuristicDraft` as the guaranteed floor.
5. **Never drop a row silently.** Anything the interpreter cannot use goes into
   `ParsedStatement.skipped` with a localized reason and is shown in
   `ImportDiagnosticsView`.
6. **No hardcoded bank, currency, or date format.** `ColumnRoleResolver`,
   `DateTokenParser`, and `MoneyTokenParser` carry every format assumption, and
   each is pinned by tests. Supporting a new bank means adding a test case
   there, not a branch elsewhere.
7. **`useLanguageCorrection` stays off.** Statement and receipt content is
   mostly numbers, merchant names, and reference codes; language correction
   silently rewrites them.

## Open question: receipt photo straight to the model (iOS 27)

iOS 27 lets the on-device model take image input (`Attachment(cgImage)` inside a
`Prompt`, gated on `LanguageModelCapabilities.Capability.vision`). Receipts are the one
place where that could beat OCR text, since a receipt's layout carries meaning the flat
text loses.

Adopting it collides with rule 1: interpretation would need pixels, which today stop at
the extraction stage. Two designs, neither chosen yet:

1. Extend the seam — an optional `CGImage` on `DocumentSnapshot` (CoreGraphics, not
   Vision/PDFKit/UIKit, so the import ban holds). Costs the struct its synthesized
   `Equatable`, which the hand-built test snapshots rely on.
2. Keep the seam — a separate vision interpreter above `ReceiptInterpreter`, which falls
   through to the text path.

`IntelligenceAvailability.supportsVision` is in place as a **probe** and
`ReceiptInterpreter` logs it on every intelligent run (Console.app, subsystem `Tenra`,
category `ReceiptInterpreter`). Decide the design only after that log shows the
capability actually exists on real devices; rule 2 still applies either way, so the
text and heuristic paths stay.

## Operation column (Покупка / Перевод / Пополнение / Снятие)

When a statement has a separate transaction-type column (Kaspi: "Операция" next to "Детали"),
`ColumnRoleResolver` assigns it `ColumnRoles.operation` and `StatementInterpreter` keeps the raw text
in `ParsedTransaction.operation`. `StatementOperationKind.classify` maps it (multilingual keywords) to
purchase / transfer / top-up / cash withdrawal / other. Money-movement rows carry the statement's own
label in the description ("Перевод · Асан Б."); purchases stay bare merchant names. Cash withdrawals
start unchecked on the review screen: the cash is spent later and logged separately, so importing the
withdrawal as an expense would count it twice. Transfers and top-ups stay checked (a transfer to a
person is real spending); the label lets the user uncheck own-account moves. Before 2026-09-24 the
column was dropped entirely. Pinned by `StatementOperationTests`.

## Category suggestions

Recognition output stays uncategorized (`ParsedTransactionMapper`); categories are
suggested at review time, because an empty category drops a row out of every category
aggregate and budget. `CategorySuggestionProvider` (`Services/Categories/`) fills the
pickers in `ImportTransactionPreviewView` and `ReceiptConfirmationView`, tier by tier:

1. **History**: the category the user used most for the same merchant and type
   (`CategorySuggestionService.buildHistoryIndex`, built in `Task.detached` on every
   import and never cached, so it always reflects the store). This tier is the
   "learning": accepted suggestions become history, no separate store exists.
2. **Brand list** (expense only): `CategorySuggestionService.brandPresets` maps known
   merchants to `CategoryPreset` ids, resolved to the user's localized preset name.
   It is an array of pairs, not a dictionary literal (Red Flag 16). Add merchants there.
3. **Voice keywords** (expense only): `VoiceInputParser.keywordCategory(in:)`.

Merchants are compared after `normalizedMerchant` (letters only, lowercased); keywords
of 4 characters or fewer must match a whole word. Every candidate goes through
`TransactionDraftService.resolveCategory`; landing on "Other" counts as no suggestion.
Picking a category on one review row fills the other rows of the same merchant that the
user has not set by hand. Rows whose category is not one of the user's categories save
as uncategorized, because `TransactionStore.validate` would reject them and the import
loop would drop them. An Apple Intelligence tier was deliberately left out: on-device
language support for the Russian-speaking primary market is uncertain.

## Balance on import

An account's balance is `initialBalance + Σ realized transactions` with no creation-date cutoff, and
accounts are usually created with the user's REAL current balance. `ImportBalanceCompensation.apply`
(`Services/Balance/`) runs after the review screen saves rows: for each touched account it shifts
`initialBalance` by the contribution of rows dated strictly BEFORE the account's creation day (they are
already in the entered balance), persisted through `BalanceCoordinator.persistInitialBalance`. Rows on or
after the creation day are new money movement and still move the balance. Accounts with
`shouldCalculateFromTransactions` are never compensated. The CSV path into existing accounts does not use
it yet. Pinned by `ImportBalanceCompensationTests`.

## Tests

`TenraTests/Services/Import/` covers `DateTokenParser`, `MoneyTokenParser`,
`ColumnRoleResolver`, `StatementInterpreter`, and `ReceiptInterpreter`'s
deterministic path. The Vision and Apple Intelligence paths are not unit
testable (device and model dependent); they are covered by the fact that both
degrade into the tested deterministic paths.

## Recent additions

- Receipts require an account selection before import (Task 14): the user
  picks the destination account in `ReceiptConfirmationView` before the
  recognized transaction can be added, since a receipt carries no account
  information of its own.
- Recognized statement transactions are reviewed as transaction cards through
  `ImportTransactionPreviewView` (Task 15), replacing the old raw-text review
  step with the same card UI used elsewhere in the app.
