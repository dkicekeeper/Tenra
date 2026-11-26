---
status: idea
type: chore
priority: 2
created: 2026-11-26
updated: 2026-11-26
---
# steps.position

**`steps.position`** (VoiceOver "Step 2 of 4" of DesignKit's `StepTracker` in the CSV import) is
not in Tenra's tables: the key takes its numbers from `defaultValue`'s interpolation, so check
on a device that a table value with `%lld` gets them before adding it.
