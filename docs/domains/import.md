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

## Header-anchored tables (`StatementTableAssembler`)

Real statements rarely start a page with the table header, and their cells wrap. Checked
against a Kaspi Gold and a Freedom Card statement (2026-09-24): the gap-split rows lost every
Kaspi merchant name (the header sat under the account summary, so columns were guessed from
content and "Операция" won the description), turned the summary block ("Доступно на ...") into
fake income rows, and scattered Freedom's vertically centered cells ("Сумма в / обработке",
10-line transfer details half above the date line) across columns.

When `ColumnRoleResolver.transactionHeaderDateIndex` finds a header line (date keyword + amount
keyword, no digits) anywhere in the document, `PDFTextLayerExtractor` hands its lines to the
pure `StatementTableAssembler` instead:

- **Records**: a date line is a line whose first word under the date header is a bare date.
  Wrapped lines between two date lines split at the widest vertical gap (record padding); when
  no gap stands out (Kaspi's steady pitch) they continue the record above. Lines above the first
  and below the last date line join only as a chain of close steps (1.25× the widest wrap step
  seen), and a line with a word straddling a column river stops the chain (footnotes, page
  headers). A centered record broken by the page end is carried to the next page's first record.
- **Columns**: the boundary between two header cells is the middle of the least-covered x run
  between their centers, measured on date lines and the lines between them. Header text position
  itself is not trusted (Freedom centers "Детали" 70pt right of its text).
- **Numbers**: date and amount columns take words from the date line only (or a line level with
  it), so a stray wrapped line never changes an amount. `isNumericCell` allows at most 3 letters;
  plain `looksLikeMoney` would call reference-number details numeric and drop their wraps.
- Lines above the first header never become rows, and a header-less continuation page reuses the
  last layout. No header anywhere: the gap-split tables stay as before.

Both real statements reconcile with the totals the banks print (per operation type, to the
tiyn). The PDFs themselves are personal and not in the repo; `StatementTableAssemblerTests`
holds anonymized geometry of both layouts.

## Operation column (Покупка / Перевод / Пополнение / Снятие)

When a statement has a separate transaction-type column (Kaspi: "Операция" next to "Детали"),
`ColumnRoleResolver` assigns it `ColumnRoles.operation` and `StatementInterpreter` keeps the raw text
in `ParsedTransaction.operation`. `StatementOperationKind.classify` maps it (multilingual keywords) to
purchase / transfer / top-up / cash withdrawal / other. Money-movement rows carry the statement's own
label in the description ("Перевод · Асан Б."); purchases stay bare merchant names. Cash withdrawals
start unchecked on the review screen: the cash is spent later and logged separately, so importing the
withdrawal as an expense would count it twice. Own-account moves (`.ownAccountTransfer`: Kaspi
"Перевод на свой счет" / "Поступление со своего счета", or a transfer/top-up whose details name a
deposit, like Freedom's "Перевод вклада по Договору") start unchecked for the same reason, with their
own hint. `classify(operation:details:)` reads the details only for transfers, top-ups and "other",
never for purchases (a merchant name is not a marker). Ordinary transfers and top-ups stay checked (a
transfer to a person is real spending). Before 2026-09-24 the column was dropped entirely. Pinned by
`StatementOperationTests`.

Descriptions: a details cell that is a whole payment order ("Плательщик: ... Назначение: ФИО: Асан
Б.. Мобильный: ...") shrinks to the counterparty's name, and IBAN account numbers are stripped as
noise.

## Statement account, transfers and learning (review screen)

- **Statement account.** `StatementBankDetector` finds the bank by the web domain its pages print
  ("www.kaspi.kz", "bankffin.kz" → registry `ffin.kz`; bank NAMES are not searched, a Freedom
  statement is full of "KASPI MAGAZIN" purchases) and matches it to an account by logo, then by name.
  The review screen shows it as "Счёт выписки"; every row in that currency goes there. Before, each
  row defaulted to the first account in its currency, so two tenge accounts meant re-picking the
  account on every row. Duplicate and transfer detection run in the view (`.task(id:)` on the
  statement account), because they depend on it.
- **Other side of a transfer.** `ImportTransferMatcher`: a row whose operation can be a transfer
  (not a purchase or cash withdrawal) and a saved plain expense/income on another regular account
  with the opposite direction, same amount and currency, within 2 days, are one transfer. Saving
  converts the saved transaction into the transfer (same id and date) and does not add the row.
  A saved transfer that already covers the row makes it start unchecked. Saved rows that are
  themselves a move from a deposit ("Перевод вклада по Договору") are never a counterpart: on real
  Kaspi + Freedom statements the chain deposit → card → other bank → a person repeats one amount on
  one day and paired the wrong rows. Real pair check (2026-09): 10 pairs, all correct.
- **Learned transfers.** `ImportTransferHistory` reads the user's saved transfers: an outgoing row on
  account A with a description that was saved as a transfer A → B is suggested as that transfer again.
  Plain spending/income with the same description votes against it, so it never overrides a merchant.
  Like category history there is no rule store: changing a row back teaches it too.
- **Subcategories.** The review row has a subcategory picker (linked subcategories of the category,
  or all when none is linked). `CategorySuggestionService.historySubcategory` suggests one per
  (type, merchant, category) from existing links. Saving links it to the row and to the category.
- **Saving.** `ImportCommitPlanner` (pure) turns row decisions into add / add-as-transfer / convert
  operations; `ImportCommitter` runs them, batch-writes subcategory links and calls
  `ImportBalanceCompensation.apply(saved:convertedLegs:)`, which now also covers a transfer's target
  account and, for a conversion, only the statement account's new leg.

- **Guards against wrong matches.** A saved row with a real category is a transfer counterpart only
  when its description reads like a money movement (a salary under "Зарплата" never becomes half of
  a transfer). Loan payments recorded through the loans screen (`accountId` = the paying account)
  cover the statement's plain expense row (`ImportDuplicateDetector.Reason.loanPayment`, ±3 days,
  exact amount). Every hint names the saved entry it matched ("Похоже, уже добавлено: «Кофе»,
  10 сентября"; the category when the entry has no description), so a coincidence can be told
  from a real duplicate on the spot.

- **Balance check.** `StatementBalanceParser` reads the closing balance the statement prints: a
  labelled line ("Доступно на 24.09.26: + 12 345,67 ₸", latest date wins, Kaspi prints the opening
  one too) or an account-table row ("KZ… KZT 27,000.50 ₸", dated by the period end; the row's ISO
  code beats the symbol, "¥" is also CNY). Only amounts with cents count. The review header shows
  it next to the statement account's balance at that date after import: the current balance rolled
  back past later transactions, plus the checked rows up to that date
  (`ImportReconciliation.importEffect`, pre-creation rows excluded like the compensation does).
  "Сходится" or "В Tenra меньше/больше на X" live as rows are checked, so misses that row matching
  cannot catch (amount off by a few tenge, two days late, entered on another account, rows on the
  account's creation day entered after the balance) show before saving. On the real statements the
  Kaspi opening balance plus every parsed row equals its printed closing balance to the tiyn.

Pinned by `ImportLearningTests`, `ImportCommitterTests`, `ImportBalanceCompensationTests`,
`ImportDuplicateDetectorTests`, `StatementBalanceParserTests`.

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
