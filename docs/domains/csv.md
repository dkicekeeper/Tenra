# CSV Import/Export Domain

Round-trip rules for CSV export/import via `CSVImportCoordinator`, `CSVExporter`, `CSVImporter`.

## TransactionType Coverage

All **8 TransactionTypes** must export/import (names match `CSVExporter.exportTypeName`):
- `expense`
- `income`
- `internal`
- `deposit_topup`
- `deposit_withdrawal`
- `deposit_interest`
- `loan_payment`
- `loan_early_repayment`

Mappings live in `CSVColumnMapping.typeMappings`, a dictionary literal: a duplicate key compiles but crashes on first access.

## Income Column Swap

For `income` rows, the `account` and `targetAccount` columns are **swapped** to enable correct round-trip:

| Direction | `account` column | `targetAccount` column |
|-----------|------------------|------------------------|
| Export | category name | account name |

On import:
- `CSVRow.effectiveAccountValue` for income reads `targetAccount`
- `effectiveCategoryValue` reads `account`

This swap is intentional.

## Columns

`date,type,amount,currency,account,category,subcategories,note,targetAccount,targetCurrency,targetAmount,convertedAmount`

A file without the 12th column (`convertedAmount`) imports too: every column is optional in the mapping screen, and an absent header reads as unmapped.

## Conversion columns (`CSVConversionColumns`)

[`CSVConversionColumns`](../../Tenra/Services/CSV/CSVConversionColumns.swift) maps a transaction's conversion fields to the columns and back; what the fields mean and how the app writes and reads them is in [currency.md](currency.md) §Writing the conversion fields. By `type`:

| Type | `targetCurrency` / `targetAmount` | `convertedAmount` |
|------|-----------------------------------|-------------------|
| `internalTransfer` | what the target account received, in its currency | what left the source account, in its currency (empty when the transfer is in it) |
| All other types | the equivalent the row shows (`TransactionConversion.displayedEquivalent`) with its currency, else a stored `convertedAmount` labelled with the account's currency | empty on export; read as the account-currency amount when a file has it |

Import (`EntityMappingService.conversionFields` → `CSVConversionColumns.importedFields`), on the resolved accounts:

- **One account, row in another currency.** The account-currency amount is the `convertedAmount` column, else `targetAmount` when its label is empty, the account's currency or the transaction's; it is stored as `convertedAmount` only. A label naming a third currency is not the account's amount and never lands in `targetAmount` (the balance engine reads `targetAmount` first, in the account's currency). With no figure in the file the amount is converted at the cached rate.
- **One account, row in its currency** (or no account). A `targetCurrency` other than the row's is kept as the display-only equivalent (`targetCurrency` / `targetAmount`); otherwise the `targetAmount` column becomes `convertedAmount`.
- **Transfer.** Source leg from the `convertedAmount` column, else the cached rate. Target leg from the target columns when the label fits the target account (an empty label is filled with it), else converted. `targetAmount` is spelled out whenever `convertedAmount` is set: without it the engine credits the target with the source leg.
- ⚠️ **No rate, no row.** A row that needs a conversion the cache and one network attempt (`TransactionConversion.loadRates`, once per import) can't give is skipped with `csvImport.error.conversionFailed` ("No exchange rate in row %d: USD → KZT"), before it creates a category. Re-importing the file later adds just the skipped rows (fingerprint dedup).
- Rows are converted at today's cached rate, not the rate of their date: a figure the file carries always wins.

Pinned by `CSVConversionColumnsTests`, `CSVConversionRoundTripTests` (export → import through `CSVImportCoordinator`, an 11-column file, the offline skip), `CSVRoundTripTests.conversionColumns`.

## Subcategories Export

`CSVExporter` resolves `TransactionSubcategoryLink` → subcategory names via lookup dictionaries.

Falls back to legacy `Transaction.subcategory` field.

## CSV Quote Parsing

RFC 4180 — peek-ahead for `""` (escaped quote).

Both `CSVImporter.parseCSVLine` and `CSVParsingService.parseCSVLine` use **index-based iteration**, not `for char in line`.

## Validation

`validateFileParallel` ordering: `TaskGroup` doesn't guarantee order — results must be sorted by `globalIndex` after collection.

## Batch Failure Recovery

`TransactionStore.addBatch()` validates ALL transactions; one failure rejects the entire batch.

`CSVImportCoordinator` retries individual `add()` calls after batch rejection.

Batches of 500 are flushed by `flushBatch()`, and the last one after the loop (unless cancelled), so a skipped last row (invalid, duplicate, no rate) never drops the rows before it.

## Localization

Strings in the CSV mapping views come from `String(localized:)` keys (`csvMapping.*`, e.g. `csvMapping.accountMappingTitle`), never inline literals.
