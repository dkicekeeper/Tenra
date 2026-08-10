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
