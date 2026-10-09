# Deferred Items — Phase 03 Performance

## Pre-existing Issues (out-of-scope for Plan 03-01)

### TransactionStore.swift — Incomplete RecurringStore Extraction

**Found during:** Plan 03-01 build verification
**Status:** Pre-existing, not caused by Plan 03-01 changes
**Errors:**
- `TransactionStore.swift:890`: cannot use mutating member on immutable value: 'recurringSeries' is a get-only property
- `TransactionStore.swift:898,911`: cannot assign through subscript: 'recurringSeries' is a get-only property
- `TransactionStore.swift:922`: cannot use mutating member on immutable value: 'recurringSeries' is a get-only property
- `TransactionStore.swift:953`: cannot use mutating member on immutable value: 'recurringOccurrences' is a get-only property

**Root cause:** `TransactionStore.swift` has local (uncommitted) changes from an incomplete Plan 03-PERF-02 RecurringStore extraction. `recurringSeries` and `recurringOccurrences` were changed to computed properties forwarding to `RecurringStore`, but extension code still tries to mutate them directly. `RecurringStore.swift` exists as an untracked file.

**Resolution:** Must be addressed in Plan 03-02 (RecurringStore extraction) before that plan can compile successfully.
