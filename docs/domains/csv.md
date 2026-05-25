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

Mappings live in `CSVColumnMapping.typeMappings`.

## Income Column Swap

For `income` rows, the `account` and `targetAccount` columns are **swapped** to enable correct round-trip:

| Direction | `account` column | `targetAccount` column |
|-----------|------------------|------------------------|
| Export | category name | account name |

On import:
- `CSVRow.effectiveAccountValue` for income reads `targetAccount`
- `effectiveCategoryValue` reads `account`

This swap is intentional.

## targetCurrency / targetAmount Dual Purpose

Determined by `type` column on import (`EntityMappingService.convertRow`):

| Type | `targetCurrency` / `targetAmount` represent |
|------|---------------------------------------------|
| `internalTransfer` | target account data |
| All other types | `convertedAmount` |

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

## Localization

Hardcoded strings in CSV mapping views are surfaced by `String(localized:)` keys — never inline Russian/English literals (see `Localizable.strings` for keys like `csv.accountMapping`).
